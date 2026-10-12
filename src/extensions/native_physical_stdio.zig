//! One physical stdin producer and serialized stdout/stderr for Main and all
//! framed native workers. Worker framing remains on its private child pipes.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const platform = @import("../tui/platform_terminal.zig");
const actual = @import("native_stdio_frontend.zig");
const bridge_mod = @import("process_stream_bridge.zig");
const protocol = @import("process_stream_protocol.zig");

// Every unmodified VTable entry receives the exact backing userdata. The
// singleton only redirects operate; all other callbacks retain their ABI.
var installed: std.atomic.Value(?*Hub) = .init(null);
const Subscription = struct { sink: bridge_mod.Sink, live: bool = true, borrowed: usize = 0 };
const Event = union(enum) { input: []const u8, end, raw: bool, resize: struct { columns: u32, rows: u32 } };
pub const Hub = struct {
    backing: Io,
    table: Io.VTable,
    allocator: std.mem.Allocator,
    mutex: Io.Mutex = .init,
    output_mutex: Io.Mutex = .init,
    delivery_mutex: Io.Mutex = .init,
    changed: Io.Condition = .init,
    console: actual.Console = .{},
    metadata: protocol.Metadata = undefined,
    main_queue: std.ArrayList(u8) = .empty,
    main_index: usize = 0,
    subscriptions: [16]?Subscription = @splat(null),
    main_enabled: bool = false,
    // Main guard transitions retain raw ownership across modal handoffs.
    // Explicit guest raw-mode control transfers that ownership back.
    main_raw_owned: bool = false,
    flowing: bool = false,
    started: bool = false,
    closing: bool = false,
    eof: bool = false,
    failure: ?anyerror = null,
    producer_group: Io.Group = .init,
    monitor_group: Io.Group = .init,
    monitor_started: bool = false,

    pub fn init(self: *Hub, allocator: std.mem.Allocator, backing: Io) !void {
        self.* = .{ .allocator = allocator, .backing = backing, .table = backing.vtable.* };
        if (installed.cmpxchgStrong(null, self, .acq_rel, .acquire) != null) return error.PhysicalStdioAlreadyBound;
        errdefer installed.store(null, .release);
        self.metadata = .{
            .stdin_tty = try Io.File.stdin().isTty(backing),
            .stdin_raw = false,
            .stdout_tty = try Io.File.stdout().isTty(backing),
            .stderr_tty = try Io.File.stderr().isTty(backing),
            .columns = null,
            .rows = null,
        };
        try self.console.init(self.metadata.stdin_tty, self.metadata.stdout_tty, self.metadata.stderr_tty);
        errdefer self.console.close();
        if (self.console.input) |original| {
            self.metadata.stdin_raw = if (comptime builtin.os.tag == .windows) original.mode & 2 == 0 else !original.lflag.ICANON;
            self.console.raw = self.metadata.stdin_raw;
        }
        const size = actual.dimensions(self.metadata.stdout_tty);
        self.metadata.columns = size.columns;
        self.metadata.rows = size.rows;
        self.table.operate = operate;
        platform.input_bridge = .{ .context = self, .buffered_fn = buffered, .poll_fn = poll, .wait_fn = wait, .raw_fn = notifyRaw };
        errdefer platform.input_bridge = null;
        try self.monitor_group.concurrent(backing, monitor, .{self});
        self.monitor_started = true;
    }
    pub fn io(self: *Hub) Io {
        return .{ .userdata = self.backing.userdata, .vtable = &self.table };
    }
    pub fn bridge(self: *Hub) bridge_mod.Bridge {
        return .{ .context = self, .guard_fn = guard, .metadata_fn = describe, .control_fn = control, .write_fn = write, .attach_fn = attach, .detach_fn = detach };
    }
    pub fn deinit(self: *Hub) void {
        self.mutex.lockUncancelable(self.backing);
        self.closing = true;
        self.changed.broadcast(self.backing);
        self.mutex.unlock(self.backing);
        if (self.started) {
            self.producer_group.cancel(self.backing);
            self.producer_group.await(self.backing) catch {};
        }
        if (self.monitor_started) {
            self.monitor_group.cancel(self.backing);
            self.monitor_group.await(self.backing) catch {};
        }
        // Host workers must detach before their owner's Hub is destroyed.
        for (self.subscriptions) |subscription| std.debug.assert(subscription == null);
        platform.input_bridge = null;
        installed.store(null, .release);
        self.console.close();
        self.main_queue.deinit(self.allocator);
    }
    fn guard(raw: ?*anyopaque) !void {
        const self: *Hub = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.backing);
        defer self.mutex.unlock(self.backing);
        if (self.closing) return error.NativeProcessFrontendClosed;
    }
    fn describe(raw: ?*anyopaque) !protocol.Metadata {
        const self: *Hub = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.backing);
        defer self.mutex.unlock(self.backing);
        if (self.closing) return error.NativeProcessFrontendClosed;
        return self.metadata;
    }
    fn monitor(self: *Hub) void {
        while (true) {
            self.backing.sleep(.fromMilliseconds(50), .awake) catch return;
            const size = actual.dimensions(self.metadata.stdout_tty);
            self.mutex.lockUncancelable(self.backing);
            if (self.closing) {
                self.mutex.unlock(self.backing);
                return;
            }
            const changed = size.columns != self.metadata.columns or size.rows != self.metadata.rows;
            self.metadata.columns = size.columns;
            self.metadata.rows = size.rows;
            self.mutex.unlock(self.backing);
            if (changed and size.columns != null and size.rows != null)
                self.publish(.{ .resize = .{ .columns = size.columns.?, .rows = size.rows.? } }) catch return;
        }
    }
    fn startLocked(self: *Hub) !void {
        if (self.started) return;
        try self.producer_group.concurrent(self.backing, produce, .{self});
        self.started = true;
    }
    fn control(raw: ?*anyopaque, op: protocol.Control) !void {
        const self: *Hub = @ptrCast(@alignCast(raw.?));
        try self.controlLocked(op);
        if (op == .raw_mode) try self.publish(.{ .raw = op.raw_mode });
    }
    fn controlLocked(self: *Hub, op: protocol.Control) !void {
        self.mutex.lockUncancelable(self.backing);
        defer self.mutex.unlock(self.backing);
        if (self.closing) return error.NativeProcessFrontendClosed;
        switch (op) {
            .raw_mode => |enabled| {
                try self.console.setRaw(enabled);
                self.metadata.stdin_raw = enabled;
                self.main_raw_owned = false;
            },
            .@"resume" => {
                try self.startLocked();
                self.flowing = true;
            },
            .pause => self.flowing = false,
            .encoding => {},
        }
        self.changed.broadcast(self.backing);
    }
    fn notifyRaw(raw: ?*anyopaque, enabled: bool) !void {
        const self: *Hub = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.backing);
        self.metadata.stdin_raw = enabled;
        self.main_raw_owned = true;
        self.console.raw = enabled;
        self.mutex.unlock(self.backing);
        try self.publish(.{ .raw = enabled });
    }
    fn write(raw: ?*anyopaque, output: protocol.Output, bytes: []const u8) !void {
        const self: *Hub = @ptrCast(@alignCast(raw.?));
        try guard(self);
        try self.output_mutex.lock(self.backing);
        defer self.output_mutex.unlock(self.backing);
        try (if (output == .stdout) Io.File.stdout() else Io.File.stderr()).writeStreamingAll(self.backing, bytes);
    }
    fn attach(raw: ?*anyopaque, sink: bridge_mod.Sink) !void {
        const self: *Hub = @ptrCast(@alignCast(raw.?));
        try self.delivery_mutex.lock(self.backing);
        defer self.delivery_mutex.unlock(self.backing);
        self.mutex.lockUncancelable(self.backing);
        if (self.closing) {
            self.mutex.unlock(self.backing);
            return error.NativeProcessFrontendClosed;
        }
        const metadata = self.metadata;
        const eof = self.eof;
        var selected: ?usize = null;
        for (&self.subscriptions, 0..) |*slot, index| if (slot.* == null) {
            slot.* = .{ .sink = sink, .borrowed = 1 };
            selected = index;
            break;
        };
        self.mutex.unlock(self.backing);
        const index = selected orelse return error.NativeProcessSubscriberLimit;
        var attached = false;
        defer {
            self.mutex.lockUncancelable(self.backing);
            self.subscriptions[index].?.borrowed -= 1;
            // A rejected bootstrap must not retain the caller's context. The
            // delivery mutex prevents a producer from borrowing this slot.
            if (!attached) self.subscriptions[index] = null;
            self.changed.broadcast(self.backing);
            self.mutex.unlock(self.backing);
        }
        // The producer can finish before a reload worker is attached. Replay
        // current physical state after its bootstrap, never previous input.
        if (metadata.stdin_tty) try sink.raw(metadata.stdin_raw);
        if (metadata.columns != null and metadata.rows != null) try sink.resize(metadata.columns.?, metadata.rows.?);
        if (eof) try sink.end();
        attached = true;
    }
    fn detach(raw: ?*anyopaque, sink: bridge_mod.Sink) void {
        const self: *Hub = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.backing);
        defer self.mutex.unlock(self.backing);
        for (&self.subscriptions) |*slot| if (slot.*) |*subscription| {
            if (!subscription.sink.matches(sink)) continue;
            subscription.live = false;
            while (subscription.borrowed != 0) self.changed.waitUncancelable(self.backing, &self.mutex);
            slot.* = null;
            return;
        };
    }
    fn publish(self: *Hub, event: Event) !void {
        try self.delivery_mutex.lock(self.backing);
        defer self.delivery_mutex.unlock(self.backing);
        var targets: [16]?bridge_mod.Sink = @splat(null);
        self.mutex.lockUncancelable(self.backing);
        for (&self.subscriptions, &targets) |*slot, *target| if (slot.*) |*subscription| {
            if (subscription.live) {
                subscription.borrowed += 1;
                target.* = subscription.sink;
            }
        };
        self.mutex.unlock(self.backing);
        defer {
            self.mutex.lockUncancelable(self.backing);
            for (&self.subscriptions, targets) |*slot, target| if (target != null) {
                slot.*.?.borrowed -= 1;
            };
            self.changed.broadcast(self.backing);
            self.mutex.unlock(self.backing);
        }
        for (targets, 0..) |target, index| if (target) |sink| {
            const delivery = switch (event) {
                .input => |input| sink.input(input),
                .end => sink.end(),
                .raw => |enabled| sink.raw(enabled),
                .resize => |size| sink.resize(size.columns, size.rows),
            };
            delivery catch {
                // One closed child cannot stop physical input or prevent
                // delivery to another live worker during replacement.
                self.mutex.lockUncancelable(self.backing);
                self.subscriptions[index].?.live = false;
                self.mutex.unlock(self.backing);
            };
        };
    }
    fn produce(self: *Hub) void {
        var buffer: [64 * 1024]u8 = undefined;
        var console_buffer: [8192]u8 = undefined;
        var console_reader = Io.File.stdin().reader(self.backing, &console_buffer);
        while (true) {
            self.mutex.lockUncancelable(self.backing);
            while (!self.closing and ((!self.main_enabled and !self.flowing) or self.main_queue.items.len - self.main_index >= 4 * 1024 * 1024))
                self.changed.waitUncancelable(self.backing, &self.mutex);
            const closing = self.closing;
            self.mutex.unlock(self.backing);
            if (closing) return;
            const count = self.readPhysical(&buffer, &console_reader) catch |err| {
                self.mutex.lockUncancelable(self.backing);
                if (!self.closing) {
                    if (err == error.EndOfStream) self.eof = true else self.failure = err;
                }
                self.changed.broadcast(self.backing);
                self.mutex.unlock(self.backing);
                if (err == error.EndOfStream) self.publish(.end) catch {};
                return;
            };
            if (count == 0) {
                self.mutex.lockUncancelable(self.backing);
                self.eof = true;
                self.changed.broadcast(self.backing);
                self.mutex.unlock(self.backing);
                self.publish(.end) catch {};
                return;
            }
            self.mutex.lockUncancelable(self.backing);
            if (self.main_enabled) self.main_queue.appendSlice(self.allocator, buffer[0..count]) catch |err| {
                self.failure = err;
                self.changed.broadcast(self.backing);
                self.mutex.unlock(self.backing);
                return;
            };
            const flowing = self.flowing;
            self.changed.broadcast(self.backing);
            self.mutex.unlock(self.backing);
            if (flowing) self.publish(.{ .input = buffer[0..count] }) catch |err| {
                self.mutex.lockUncancelable(self.backing);
                self.failure = err;
                self.changed.broadcast(self.backing);
                self.mutex.unlock(self.backing);
                return;
            };
        }
    }
    fn pollPhysical(self: *Hub, reader: *Io.File.Reader) !?u8 {
        self.mutex.lockUncancelable(self.backing);
        const raw_only = self.main_enabled and self.main_raw_owned;
        self.mutex.unlock(self.backing);
        return if (raw_only) platform.pollBytePhysicalRaw(reader) else platform.pollBytePhysical(reader);
    }
    fn readPhysical(self: *Hub, buffer: []u8, console_reader: *Io.File.Reader) !usize {
        if (comptime builtin.os.tag == .windows) if (self.metadata.stdin_tty) {
            var count: usize = 0;
            while (count == 0) {
                try self.backing.checkCancel();
                if (try self.pollPhysical(console_reader)) |byte| {
                    buffer[0] = byte;
                    count = 1;
                } else try self.backing.sleep(.fromMilliseconds(10), .awake);
            }
            // ReadConsoleW decodes an entire available burst into the shared
            // physical console decoder, rather than File.Reader's byte buffer.
            // Retain that burst before publishing one input turn to Main.
            while (count < buffer.len and platform.inputBufferedPhysical(console_reader)) {
                buffer[count] = (try self.pollPhysical(console_reader)) orelse break;
                count += 1;
            }
            return count;
        };
        var vectors = [_][]u8{buffer};
        return Io.File.stdin().readStreaming(self.backing, &vectors);
    }
    fn enableMain(self: *Hub) !void {
        self.main_enabled = true;
        try self.startLocked();
        self.changed.broadcast(self.backing);
    }
    fn buffered(raw: ?*anyopaque) bool {
        const self: *Hub = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.backing);
        defer self.mutex.unlock(self.backing);
        return self.main_index < self.main_queue.items.len;
    }
    fn poll(raw: ?*anyopaque) !?u8 {
        const self: *Hub = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.backing);
        defer self.mutex.unlock(self.backing);
        try self.enableMain();
        if (self.main_index < self.main_queue.items.len) {
            const byte = self.main_queue.items[self.main_index];
            self.main_index += 1;
            self.compactLocked();
            return byte;
        }
        if (self.failure) |failure| return failure;
        if (self.eof or self.closing) return error.EndOfStream;
        return null;
    }
    fn compactLocked(self: *Hub) void {
        if (self.main_index == self.main_queue.items.len) {
            self.main_queue.clearRetainingCapacity();
            self.main_index = 0;
        } else if (self.main_index >= 64 * 1024) {
            const remaining = self.main_queue.items.len - self.main_index;
            std.mem.copyForwards(u8, self.main_queue.items[0..remaining], self.main_queue.items[self.main_index..]);
            self.main_queue.shrinkRetainingCapacity(remaining);
            self.main_index = 0;
        }
        self.changed.broadcast(self.backing);
    }
    fn wait(raw: ?*anyopaque, timeout_ms: u32) !platform.Ready {
        const self: *Hub = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.backing);
        defer self.mutex.unlock(self.backing);
        try self.enableMain();
        const deadline = Io.Clock.awake.now(self.backing).toMilliseconds() +| timeout_ms;
        while (self.main_index == self.main_queue.items.len and !self.eof and !self.closing and self.failure == null) {
            const remaining = deadline - Io.Clock.awake.now(self.backing).toMilliseconds();
            if (remaining <= 0) return .timeout;
            self.mutex.unlock(self.backing);
            const slept = self.backing.sleep(.fromMilliseconds(@intCast(@min(remaining, 10))), .awake);
            self.mutex.lockUncancelable(self.backing);
            try slept;
        }
        if (self.main_index < self.main_queue.items.len) return .input;
        if (self.failure) |failure| return failure;
        return .dead;
    }
    fn readMain(self: *Hub, vectors: []const []u8) !usize {
        _ = try wait(self, std.math.maxInt(u32));
        self.mutex.lockUncancelable(self.backing);
        defer self.mutex.unlock(self.backing);
        var copied: usize = 0;
        for (vectors) |vector| {
            const count = @min(vector.len, self.main_queue.items.len - self.main_index);
            @memcpy(vector[0..count], self.main_queue.items[self.main_index..][0..count]);
            self.main_index += count;
            copied += count;
            if (count != vector.len) break;
        }
        self.compactLocked();
        if (copied == 0 and (self.eof or self.closing)) return error.EndOfStream;
        return copied;
    }
    fn operate(raw: ?*anyopaque, operation: Io.Operation) Io.Cancelable!Io.Operation.Result {
        const self = installed.load(.acquire) orelse unreachable;
        std.debug.assert(raw == self.backing.userdata);
        switch (operation) {
            .file_read_streaming => |read| if (read.file.handle == Io.File.stdin().handle) {
                const count = self.readMain(read.data) catch |err| {
                    if (err == error.Canceled) return error.Canceled;
                    return .{ .file_read_streaming = if (err == error.EndOfStream) error.EndOfStream else error.InputOutput };
                };
                return .{ .file_read_streaming = count };
            },
            .file_write_streaming => |write_op| if (write_op.file.handle == Io.File.stdout().handle or write_op.file.handle == Io.File.stderr().handle) {
                try self.output_mutex.lock(self.backing);
                defer self.output_mutex.unlock(self.backing);
                return self.backing.vtable.operate(raw, operation);
            },
            else => {},
        }
        return self.backing.vtable.operate(raw, operation);
    }
};

test "physical stdio adapter retains backing userdata and forwards genuine unrelated file IO" {
    const backing = std.testing.io;
    var hub: Hub = .{ .backing = backing, .table = backing.vtable.*, .allocator = std.testing.allocator };
    try std.testing.expect(installed.cmpxchgStrong(null, &hub, .acq_rel, .acquire) == null);
    defer installed.store(null, .release);
    hub.table.operate = Hub.operate;
    const adapted = hub.io();
    try std.testing.expect(adapted.userdata == backing.userdata);
    try std.testing.expect(adapted.vtable.groupConcurrent == backing.vtable.groupConcurrent);
    try std.testing.expect(adapted.vtable.dirOpenFile == backing.vtable.dirOpenFile);
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    const file = try scratch.dir.createFile(adapted, "forwarded.txt", .{});
    defer file.close(adapted);
    try file.writeStreamingAll(adapted, "unchanged backing context");
    const contents = try scratch.dir.readFileAlloc(backing, "forwarded.txt", std.testing.allocator, .limited(128));
    defer std.testing.allocator.free(contents);
    try std.testing.expectEqualStrings("unchanged backing context", contents);
}
test "physical stdio Main adapter consumes one retained byte queue across poll and vector reads before EOF" {
    const backing = std.testing.io;
    var hub: Hub = .{ .backing = backing, .table = backing.vtable.*, .allocator = std.testing.allocator, .started = true, .main_enabled = true, .eof = true };
    defer hub.main_queue.deinit(std.testing.allocator);
    try hub.main_queue.appendSlice(std.testing.allocator, "aΩ🦊z");
    try std.testing.expect(installed.cmpxchgStrong(null, &hub, .acq_rel, .acquire) == null);
    defer installed.store(null, .release);
    hub.table.operate = Hub.operate;
    try std.testing.expectEqual(platform.Ready.input, try Hub.wait(&hub, 0));
    try std.testing.expectEqual(@as(?u8, 'a'), try Hub.poll(&hub));
    var first: [2]u8 = undefined;
    var second: [5]u8 = undefined;
    var vectors = [_][]u8{ &first, &second };
    try std.testing.expectEqual(@as(usize, 7), try Io.File.stdin().readStreaming(hub.io(), &vectors));
    try std.testing.expectEqualStrings("Ω", &first);
    try std.testing.expectEqualStrings("🦊z", &second);
    try std.testing.expectEqual(platform.Ready.dead, try Hub.wait(&hub, 0));
    try std.testing.expectError(error.EndOfStream, Io.File.stdin().readStreaming(hub.io(), &vectors));
}
test "physical stdio broadcasts past a failed retiring sink and replays EOF to a later replacement" {
    const Fixture = struct {
        fail: bool = false,
        inputs: usize = 0,
        ends: usize = 0,
        fn input(raw: ?*anyopaque, _: protocol.Lease, bytes: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (self.fail) return error.RetiringChildClosed;
            try std.testing.expectEqualStrings("physical", bytes);
            self.inputs += 1;
        }
        fn end(raw: ?*anyopaque, _: protocol.Lease) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.ends += 1;
        }
        fn resize(_: ?*anyopaque, _: protocol.Lease, _: u32, _: u32) !void {}
        fn sink(self: *@This(), generation: u64) bridge_mod.Sink {
            return .{ .context = self, .lease = .{ .owner_generation = 1, .process_generation = generation }, .input_fn = input, .end_fn = end, .resize_fn = resize };
        }
    };
    const backing = std.testing.io;
    var hub: Hub = .{ .backing = backing, .table = backing.vtable.*, .allocator = std.testing.allocator, .metadata = .{ .stdin_tty = false, .stdin_raw = false, .stdout_tty = false, .stderr_tty = false, .columns = null, .rows = null } };
    var retiring: Fixture = .{ .fail = true };
    var current: Fixture = .{};
    try Hub.attach(&hub, retiring.sink(1));
    defer Hub.detach(&hub, retiring.sink(1));
    try Hub.attach(&hub, current.sink(2));
    defer Hub.detach(&hub, current.sink(2));
    try hub.publish(.{ .input = "physical" });
    try std.testing.expectEqual(@as(usize, 1), current.inputs);
    hub.eof = true;
    var replacement: Fixture = .{};
    try Hub.attach(&hub, replacement.sink(3));
    defer Hub.detach(&hub, replacement.sink(3));
    try std.testing.expectEqual(@as(usize, 1), replacement.ends);
}

test "physical stdio failed bootstrap releases subscriber context without requiring paired detach" {
    const Fixture = struct {
        fn input(_: ?*anyopaque, _: protocol.Lease, _: []const u8) !void {}
        fn end(_: ?*anyopaque, _: protocol.Lease) !void {
            return error.BootstrapRejected;
        }
        fn resize(_: ?*anyopaque, _: protocol.Lease, _: u32, _: u32) !void {}
    };
    const backing = std.testing.io;
    var hub: Hub = .{ .backing = backing, .table = backing.vtable.*, .allocator = std.testing.allocator, .eof = true, .metadata = .{ .stdin_tty = false, .stdin_raw = false, .stdout_tty = false, .stderr_tty = false, .columns = null, .rows = null } };
    const sink: bridge_mod.Sink = .{ .context = null, .lease = .{ .owner_generation = 1, .process_generation = 1 }, .input_fn = Fixture.input, .end_fn = Fixture.end, .resize_fn = Fixture.resize };
    for (0..32) |_| {
        try std.testing.expectError(error.BootstrapRejected, Hub.attach(&hub, sink));
        for (hub.subscriptions) |subscription| try std.testing.expect(subscription == null);
    }
}

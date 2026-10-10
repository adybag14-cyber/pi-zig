//! Owned JSON requests cross worker threads; only drain's owner invokes callbacks.
const std = @import("std");
const json = @import("../durable/backend/json.zig");
pub const Identity = struct { owner_generation: u64, task_id: u64, invocation_generation: u64 };
pub const Dispatch = *const fn (?*anyopaque, Identity, json.Value, *const std.atomic.Value(bool)) anyerror!json.Owned;
pub const Notify = struct { context: ?*anyopaque = null, call: ?*const fn (?*anyopaque) void = null };
const Request = struct {
    identity: Identity,
    payload: json.Owned,
    response: ?json.Owned = null,
    failure: ?anyerror = null,
    mutex: std.Io.Mutex = .init,
    done: std.Io.Event = .unset,
    settled: bool = false,
    canceled: std.atomic.Value(bool) = .init(false),
    refs: std.atomic.Value(usize) = .init(2),
    fn release(self: *Request) void {
        if (self.refs.fetchSub(1, .acq_rel) == 1) {
            self.payload.deinit();
            if (self.response) |*response| response.deinit();
            std.heap.page_allocator.destroy(self);
        }
    }
    fn fail(self: *Request, io: std.Io, cause: anyerror) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        if (self.settled) return;
        self.canceled.store(true, .release);
        self.failure = cause;
        self.settled = true;
        self.done.set(io);
    }
};
pub const Broker = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    owner: std.Thread.Id,
    owner_generation: u64,
    notify: Notify,
    mutex: std.Io.Mutex = .init,
    queue: std.ArrayList(*Request) = .empty,
    active: std.ArrayList(*Request) = .empty,
    closed: bool = false,
    calls: std.atomic.Value(usize) = .init(0),
    pub fn init(gpa: std.mem.Allocator, io: std.Io, generation: u64, notify: Notify) Broker {
        return .{ .gpa = gpa, .io = io, .owner = std.Thread.getCurrentId(), .owner_generation = generation, .notify = notify };
    }
    pub fn deinit(self: *Broker) void {
        std.debug.assert(std.Thread.getCurrentId() == self.owner);
        self.close();
        std.debug.assert(self.calls.load(.acquire) == 0 and self.active.items.len == 0);
        self.queue.deinit(std.heap.page_allocator);
        self.active.deinit(self.gpa);
    }
    /// Close is owner-only. Callers settle independently from an in-flight callback.
    /// The caller must join its workers before deinit; request refs survive late callbacks.
    pub fn close(self: *Broker) void {
        std.debug.assert(std.Thread.getCurrentId() == self.owner);
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.closed) return;
        self.closed = true;
        for (self.queue.items) |request| {
            request.fail(self.io, error.OwnerBrokerClosed);
            request.release();
        }
        self.queue.clearRetainingCapacity();
        for (self.active.items) |request| request.fail(self.io, error.OwnerBrokerClosed);
        if (self.notify.call) |notify| notify(self.notify.context);
    }
    /// No VM value or callback crosses this boundary. Payload and reply detach.
    pub fn call(self: *Broker, gpa: std.mem.Allocator, identity: Identity, payload: json.Value, canceled: ?*const std.atomic.Value(bool)) !json.Owned {
        if (std.Thread.getCurrentId() == self.owner) return error.OwnerBrokerCallOnOwner;
        const request = try std.heap.page_allocator.create(Request);
        var published = false;
        var payload_ready = false;
        errdefer if (!published) {
            if (payload_ready) request.payload.deinit();
            std.heap.page_allocator.destroy(request);
        };
        request.* = .{ .identity = identity, .payload = try json.Owned.empty(std.heap.page_allocator) };
        payload_ready = true;
        request.payload.value = try json.clone(request.payload.arena.allocator(), payload);
        self.mutex.lockUncancelable(self.io);
        if (self.closed or self.queue.items.len >= 64) {
            const failure = if (self.closed) error.OwnerBrokerClosed else error.OwnerBrokerQueueFull;
            self.mutex.unlock(self.io);
            return failure;
        }
        self.queue.append(std.heap.page_allocator, request) catch |err| {
            self.mutex.unlock(self.io);
            return err;
        };
        _ = self.calls.fetchAdd(1, .acq_rel);
        published = true;
        self.mutex.unlock(self.io);
        defer _ = self.calls.fetchSub(1, .acq_rel);
        defer request.release();
        if (self.notify.call) |notify| notify(self.notify.context);
        while (true) {
            if (canceled) |flag| if (flag.load(.acquire)) request.fail(self.io, error.Canceled);
            request.done.waitTimeout(self.io, .{ .duration = .{ .raw = .fromMilliseconds(10), .clock = .awake } }) catch |err| switch (err) {
                error.Timeout => continue,
                else => {
                    request.fail(self.io, err);
                },
            };
            request.mutex.lockUncancelable(self.io);
            defer request.mutex.unlock(self.io);
            if (request.failure) |failure| return failure;
            var result = try json.Owned.empty(gpa);
            errdefer result.deinit();
            result.value = try json.clone(result.arena.allocator(), request.response.?.value);
            return result;
        }
    }
    pub fn pending(self: *Broker) usize {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.queue.items.len;
    }
    fn failPending(self: *Broker, cause: anyerror) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (self.queue.items) |request| {
            request.fail(self.io, cause);
            request.release();
        }
        self.queue.clearRetainingCapacity();
    }
    /// Admission order is FIFO. Dispatch may pump/re-enter this owner drain.
    pub fn drain(self: *Broker, dispatch: Dispatch, context: ?*anyopaque) !bool {
        if (std.Thread.getCurrentId() != self.owner) return error.OwnerBrokerDrainOnWorker;
        var worked = false;
        while (true) {
            if (self.pending() == 0) return worked;
            // Reserve owner metadata before consuming the queue reference.
            self.active.ensureUnusedCapacity(self.gpa, 1) catch |err| {
                self.failPending(err);
                return err;
            };
            self.mutex.lockUncancelable(self.io);
            if (self.queue.items.len == 0) {
                self.mutex.unlock(self.io);
                return worked;
            }
            const request = self.queue.orderedRemove(0);
            self.mutex.unlock(self.io);
            self.active.appendAssumeCapacity(request);
            defer {
                for (self.active.items, 0..) |active, index| if (active == request) {
                    _ = self.active.orderedRemove(index);
                    break;
                };
                request.release();
            }
            worked = true;
            if (request.identity.owner_generation != self.owner_generation) {
                request.fail(self.io, error.StaleOwnerGeneration);
                continue;
            }
            if (request.canceled.load(.acquire)) continue;
            var reply = dispatch(context, request.identity, request.payload.value, &request.canceled) catch |err| {
                request.fail(self.io, err);
                continue;
            };
            defer reply.deinit();
            var copied = json.Owned.empty(std.heap.page_allocator) catch |err| {
                request.fail(self.io, err);
                continue;
            };
            copied.value = json.clone(copied.arena.allocator(), reply.value) catch |err| {
                copied.deinit();
                request.fail(self.io, err);
                continue;
            };
            request.mutex.lockUncancelable(self.io);
            if (request.settled) {
                copied.deinit();
            } else {
                request.response = copied;
                request.settled = true;
                request.done.set(self.io);
            }
            request.mutex.unlock(self.io);
        }
    }
};

test "native durable VM owner broker transfers real worker JSON and rejects stale owner generations" {
    const io = std.testing.io;
    var broker = Broker.init(std.testing.allocator, io, 7, .{});
    defer broker.deinit();
    const Worker = struct {
        broker: *Broker,
        generation: u64,
        error_value: ?anyerror = null,
        value: ?json.Owned = null,
        fn run(self: *@This()) void {
            self.value = self.broker.call(std.testing.allocator, .{ .owner_generation = self.generation, .task_id = 9, .invocation_generation = 2 }, .{ .string = "owned-Ω" }, null) catch |err| {
                self.error_value = err;
                return;
            };
        }
    };
    const Owner = struct {
        fn dispatch(raw: ?*anyopaque, identity: Identity, value: json.Value, _: *const std.atomic.Value(bool)) !json.Owned {
            const owner: *std.Thread.Id = @ptrCast(@alignCast(raw.?));
            try std.testing.expectEqual(owner.*, std.Thread.getCurrentId());
            try std.testing.expectEqual(@as(u64, 9), identity.task_id);
            try std.testing.expectEqual(@as(u64, 2), identity.invocation_generation);
            var result = try json.Owned.empty(std.testing.allocator);
            errdefer result.deinit();
            result.value = try json.clone(result.arena.allocator(), value);
            return result;
        }
    };
    var worker: Worker = .{ .broker = &broker, .generation = 7 };
    const thread = try std.Thread.spawn(.{}, Worker.run, .{&worker});
    while (broker.pending() == 0) try io.sleep(.fromMilliseconds(1), .awake);
    var owner = std.Thread.getCurrentId();
    _ = try broker.drain(Owner.dispatch, &owner);
    thread.join();
    try std.testing.expect(worker.error_value == null);
    try std.testing.expectEqualStrings("owned-Ω", worker.value.?.value.string);
    worker.value.?.deinit();
    worker = .{ .broker = &broker, .generation = 6 };
    const stale_thread = try std.Thread.spawn(.{}, Worker.run, .{&worker});
    while (broker.pending() == 0) try io.sleep(.fromMilliseconds(1), .awake);
    _ = try broker.drain(Owner.dispatch, &owner);
    stale_thread.join();
    try std.testing.expectEqual(error.StaleOwnerGeneration, worker.error_value.?);
}

test "native durable VM owner broker invokes the actual C VM only on its owner" {
    const engine_module = @import("engine.zig");
    const durable = @import("native_durable.zig");
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const callback = try engine.eval("async (identity,value)=>{const result={task:identity.task_id,invocation:identity.invocation_generation,text:value+'-owner'};globalThis.finishFromWorker(result);return result}", "owner-queue-user-fixture", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(callback);
    const promise = try engine.eval("new Promise(resolve=>globalThis.finishFromWorker=resolve)", "owner-queue-waiter-fixture", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(promise);
    var broker = Broker.init(std.testing.allocator, std.testing.io, 71, .{});
    defer broker.deinit();
    const Worker = struct {
        broker: *Broker,
        output: ?json.Owned = null,
        failure: ?anyerror = null,
        thread_id: std.Thread.Id = 0,
        fn run(self: *@This()) void {
            self.thread_id = std.Thread.getCurrentId();
            self.output = self.broker.call(std.testing.allocator, .{ .owner_generation = 71, .task_id = 11, .invocation_generation = 5 }, .{ .string = "Ω" }, null) catch |err| {
                self.failure = err;
                return;
            };
        }
    };
    const Owner = struct {
        engine: *engine_module.Engine,
        function: engine_module.c.JSValue,
        thread_id: std.Thread.Id,
        broker: *Broker,
        fn pump(engine_pointer: *engine_module.Engine) !bool {
            const self: *@This() = @ptrCast(@alignCast(engine_pointer.native_durable_control_context.?));
            return self.broker.drain(run, self);
        }
        fn run(raw: ?*anyopaque, identity: Identity, value: json.Value, _: *const std.atomic.Value(bool)) !json.Owned {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            try std.testing.expectEqual(self.thread_id, std.Thread.getCurrentId());
            const sdk = @import("native_sdk.zig");
            const input = try sdk.object(self.engine);
            defer self.engine.freeValue(input);
            try sdk.put(self.engine, input, "task_id", engine_module.c.JS_NewInt64(self.engine.context, @intCast(identity.task_id)));
            try sdk.put(self.engine, input, "invocation_generation", engine_module.c.JS_NewInt64(self.engine.context, @intCast(identity.invocation_generation)));
            const payload = try durable.jsValue(self.engine, value);
            defer self.engine.freeValue(payload);
            var args = [_]engine_module.c.JSValue{ input, payload };
            const pending = try self.engine.checked(engine_module.c.JS_Call(self.engine.context, self.function, engine_module.c.pi_js_undefined(), args.len, &args));
            defer self.engine.freeValue(pending);
            const output = try self.engine.awaitValue(pending);
            defer self.engine.freeValue(output);
            return durable.owned(self.engine, output);
        }
    };
    var worker: Worker = .{ .broker = &broker };
    const thread = try std.Thread.spawn(.{}, Worker.run, .{&worker});
    var owner: Owner = .{ .engine = engine, .function = callback, .thread_id = std.Thread.getCurrentId(), .broker = &broker };
    engine.native_durable_control_context = &owner;
    engine.native_durable_control_pump = Owner.pump;
    defer {
        engine.native_durable_control_pump = null;
        engine.native_durable_control_context = null;
    }
    const delivered = try engine.awaitValue(promise);
    defer engine.freeValue(delivered);
    thread.join();
    defer if (worker.output) |*output| output.deinit();
    try std.testing.expect(worker.thread_id != owner.thread_id and worker.failure == null);
    var expected = try json.Owned.parse(std.testing.allocator, "{\"task\":11,\"invocation\":5,\"text\":\"Ω-owner\"}");
    defer expected.deinit();
    try std.testing.expect(json.equal(expected.value, worker.output.?.value));
}

test "native durable VM owner broker cancellation and close retire queued requests before worker joins" {
    const Worker = struct {
        broker: *Broker,
        flag: *const std.atomic.Value(bool),
        failure: ?anyerror = null,
        fn run(self: *@This()) void {
            var result = self.broker.call(std.testing.allocator, .{ .owner_generation = 1, .task_id = 2, .invocation_generation = 3 }, .null, self.flag) catch |err| {
                self.failure = err;
                return;
            };
            result.deinit();
        }
    };
    const Owner = struct {
        fn forbidden(_: ?*anyopaque, _: Identity, _: json.Value, _: *const std.atomic.Value(bool)) !json.Owned {
            return error.CanceledDispatchMustNotRun;
        }
    };
    var broker = Broker.init(std.testing.allocator, std.testing.io, 1, .{});
    defer broker.deinit();
    var canceled = std.atomic.Value(bool).init(false);
    var worker: Worker = .{ .broker = &broker, .flag = &canceled };
    const thread = try std.Thread.spawn(.{}, Worker.run, .{&worker});
    while (broker.pending() == 0) try std.testing.io.sleep(.fromMilliseconds(1), .awake);
    canceled.store(true, .release);
    thread.join();
    try std.testing.expectEqual(error.Canceled, worker.failure.?);
    _ = try broker.drain(Owner.forbidden, null);
    canceled.store(false, .release);
    worker = .{ .broker = &broker, .flag = &canceled };
    const closing_thread = try std.Thread.spawn(.{}, Worker.run, .{&worker});
    while (broker.pending() == 0) try std.testing.io.sleep(.fromMilliseconds(1), .awake);
    broker.close();
    closing_thread.join();
    try std.testing.expectEqual(error.OwnerBrokerClosed, worker.failure.?);
    try std.testing.expectEqual(@as(usize, 0), broker.pending());
}

test "native durable VM owner broker callback can close in flight without retiring its request before reply cleanup" {
    const Worker = struct {
        broker: *Broker,
        failure: ?anyerror = null,
        fn run(self: *@This()) void {
            var output = self.broker.call(std.testing.allocator, .{ .owner_generation = 1, .task_id = 2, .invocation_generation = 3 }, .null, null) catch |err| {
                self.failure = err;
                return;
            };
            output.deinit();
        }
    };
    const Owner = struct {
        fn close(raw: ?*anyopaque, _: Identity, _: json.Value, canceled: *const std.atomic.Value(bool)) !json.Owned {
            const broker: *Broker = @ptrCast(@alignCast(raw.?));
            broker.close();
            try std.testing.expect(canceled.load(.acquire));
            return json.Owned.empty(std.testing.allocator);
        }
    };
    var broker = Broker.init(std.testing.allocator, std.testing.io, 1, .{});
    defer broker.deinit();
    var worker: Worker = .{ .broker = &broker };
    const thread = try std.Thread.spawn(.{}, Worker.run, .{&worker});
    while (broker.pending() == 0) try std.testing.io.sleep(.fromMilliseconds(1), .awake);
    _ = try broker.drain(Owner.close, &broker);
    thread.join();
    try std.testing.expectEqual(error.OwnerBrokerClosed, worker.failure.?);
    try std.testing.expectEqual(@as(usize, 0), broker.active.items.len);
}

test "native durable VM owner broker GPA failure settles waiters and allows a later owner drain" {
    const Worker = struct {
        broker: *Broker,
        failure: ?anyerror = null,
        fn run(self: *@This()) void {
            var output = self.broker.call(std.testing.allocator, .{ .owner_generation = 1, .task_id = 2, .invocation_generation = 3 }, .null, null) catch |err| {
                self.failure = err;
                return;
            };
            output.deinit();
        }
    };
    const Owner = struct {
        fn run(_: ?*anyopaque, _: Identity, _: json.Value, _: *const std.atomic.Value(bool)) !json.Owned {
            return json.Owned.empty(std.testing.allocator);
        }
    };
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var broker = Broker.init(failing.allocator(), std.testing.io, 1, .{});
    defer broker.deinit();
    var worker: Worker = .{ .broker = &broker };
    const thread = try std.Thread.spawn(.{}, Worker.run, .{&worker});
    while (broker.pending() == 0) try std.testing.io.sleep(.fromMilliseconds(1), .awake);
    try std.testing.expectError(error.OutOfMemory, broker.drain(Owner.run, null));
    thread.join();
    try std.testing.expectEqual(error.OutOfMemory, worker.failure.?);
    failing.fail_index = std.math.maxInt(usize);
    worker = .{ .broker = &broker };
    const next = try std.Thread.spawn(.{}, Worker.run, .{&worker});
    while (broker.pending() == 0) try std.testing.io.sleep(.fromMilliseconds(1), .awake);
    _ = try broker.drain(Owner.run, null);
    next.join();
    try std.testing.expect(worker.failure == null);
}

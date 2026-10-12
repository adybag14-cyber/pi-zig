//! A fresh native thread owns one controlled VM. Only owned JSON crosses the
//! channel; the caller never accesses the worker's C context or JS values.
const std = @import("std");
const run_mod = @import("codemode_run.zig");
const host_mod = @import("codemode_run_host.zig");
const json = @import("protocol.zig").json;
const Signal = @import("../extensions/native_owner_signal.zig").Signal;
pub const Options = struct {
    started_at: f64,
    seed: f64,
    tools: []const run_mod.Tool = &.{},
    globals: []const run_mod.Global = &.{},
    store: json.Value = .{ .object = .empty },
    timeout_ms: ?u64 = null,
    memory_limit: usize = 64 * 1024 * 1024,
    stack_limit: usize = 1024 * 1024,
    interrupt_budget: ?f64 = null,
    notify_context: ?*anyopaque = null,
    /// Must be thread-safe and must not call a VM. Its lease outlives join().
    notify: ?*const fn (?*anyopaque) void = null,
};
const Node = struct { value: json.Owned, next: ?*Node = null };
const Queue = struct {
    first: ?*Node = null,
    last: ?*Node = null,
    count: usize = 0,
    fn append(self: *Queue, node: *Node) void {
        if (self.last) |last| last.next = node else self.first = node;
        self.last = node;
        self.count += 1;
    }
    fn pop(self: *Queue) ?*Node {
        const node = self.first orelse return null;
        self.first = node.next;
        if (self.first == null) self.last = null;
        self.count -= 1;
        node.next = null;
        return node;
    }
};
pub const Session = struct {
    parent: std.mem.Allocator,
    io: std.Io,
    allocation_mutex: std.Io.Mutex = .init,
    channel_mutex: std.Io.Mutex = .init,
    inputs: std.heap.ArenaAllocator,
    source: []const u8,
    options: Options,
    events: Queue = .{},
    commands: Queue = .{},
    owner_signal: Signal = .{},
    worker_signal: Signal = .{},
    abort_requested: bool = false,
    completed: std.atomic.Value(bool) = .init(false),
    failure: ?anyerror = null,
    thread: ?std.Thread = null,
    launched: bool = false,
    owner: std.Thread.Id,

    pub fn create(parent: std.mem.Allocator, io: std.Io, source: []const u8, options: Options) !*Session {
        var validation = try host_mod.Host.init(parent, options.started_at, options.seed);
        defer validation.deinit();
        try run_mod.validateDeclarations(parent, options.tools, options.globals);
        const self = try parent.create(Session);
        self.* = .{ .parent = parent, .io = io, .inputs = undefined, .source = "", .options = options, .owner = std.Thread.getCurrentId() };
        self.inputs = std.heap.ArenaAllocator.init(self.allocator());
        errdefer {
            self.inputs.deinit();
            parent.destroy(self);
        }
        const a = self.inputs.allocator();
        self.source = try a.dupe(u8, source);
        const tools = try a.alloc(run_mod.Tool, options.tools.len);
        for (tools, options.tools) |*tool, original| tool.* = .{ .name = try a.dupe(u8, original.name), .js_name = if (original.js_name) |name| try a.dupe(u8, name) else null, .description = try a.dupe(u8, original.description) };
        self.options.tools = tools;
        const globals = try a.alloc(run_mod.Global, options.globals.len);
        for (globals, options.globals) |*global, original| global.* = .{ .name = try a.dupe(u8, original.name), .spread = original.spread };
        self.options.globals = globals;
        self.options.store = try json.clone(a, options.store);
        return self;
    }
    /// Publication is separate from construction. No callback can run before
    /// the caller has installed its host execution and cancellation owner.
    pub fn start(self: *Session) !void {
        self.assertOwner();
        if (self.launched) return error.WorkerAlreadyStarted;
        const thread = try std.Thread.spawn(.{ .stack_size = 8 * 1024 * 1024 }, workerMain, .{self});
        self.thread = thread;
        self.launched = true;
    }
    pub fn abort(self: *Session) void {
        self.assertOwner();
        @atomicStore(bool, &self.abort_requested, true, .release);
        self.worker_signal.notify(self.io);
    }
    pub fn join(self: *Session) void {
        self.assertOwner();
        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }
    }
    pub fn deinit(self: *Session) void {
        self.abort();
        self.join();
        self.clear(&self.events);
        self.clear(&self.commands);
        self.inputs.deinit();
        const parent = self.parent;
        parent.destroy(self);
    }
    pub fn isCompleted(self: *const Session) bool {
        return self.completed.load(.acquire);
    }
    /// Receives an owned event. Release it before destroying this Session;
    /// its allocator is guarded by the Session's live allocation mutex.
    pub fn next(self: *Session) !?json.Owned {
        self.assertOwner();
        self.channel_mutex.lockUncancelable(self.io);
        const node = self.events.pop();
        self.channel_mutex.unlock(self.io);
        if (node) |value| {
            const result = value.value;
            self.allocator().destroy(value);
            return result;
        }
        if (self.isCompleted()) if (self.failure) |failure| return failure;
        return null;
    }
    pub fn wait(self: *Session, timeout: std.Io.Timeout) !void {
        self.assertOwner();
        const observed = self.owner_signal.observe();
        self.channel_mutex.lockUncancelable(self.io);
        const ready = self.events.first != null;
        self.channel_mutex.unlock(self.io);
        if (ready or self.isCompleted()) return;
        _ = try self.owner_signal.waitAfter(self.io, observed, timeout);
    }
    /// A transport post. The owning host execution validates ids, serialization
    /// and sequence numbers before posting; worker Run independently admits it.
    pub fn post(self: *Session, seq: f64, now: f64, id: u64, outcome: host_mod.Outcome) !void {
        self.assertOwner();
        if (self.isCompleted()) return;
        const gpa = self.allocator();
        var value = try json.Owned.empty(gpa);
        errdefer value.deinit();
        const a = value.arena.allocator();
        value.value = .{ .object = .empty };
        try value.value.object.put(a, "seq", .{ .float = seq });
        try value.value.object.put(a, "now", .{ .float = now });
        try value.value.object.put(a, "id", .{ .integer = @intCast(id) });
        try value.value.object.put(a, "ok", .{ .bool = outcome == .success });
        switch (outcome) {
            .success => |payload| if (payload) |bytes| try value.value.object.put(a, "payload", .{ .string = try a.dupe(u8, bytes) }),
            .failure => |failure| {
                try value.value.object.put(a, "payload", .{ .string = try a.dupe(u8, failure.message) });
                try value.value.object.put(a, "propertiesWasObject", .{ .bool = failure.properties_was_object });
                if (failure.properties) |bytes| try value.value.object.put(a, "properties", .{ .string = try a.dupe(u8, bytes) });
            },
        }
        try self.enqueue(&self.commands, value);
        self.worker_signal.notify(self.io);
    }
    fn assertOwner(self: *const Session) void {
        std.debug.assert(self.owner == std.Thread.getCurrentId());
    }
    // Guard the supplied allocator as well as the queue: VM allocations occur
    // on the worker while incoming/outgoing JSON can be owned by the caller.
    fn allocator(self: *Session) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn alloc(raw: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *Session = @ptrCast(@alignCast(raw));
        self.allocation_mutex.lockUncancelable(self.io);
        defer self.allocation_mutex.unlock(self.io);
        return self.parent.rawAlloc(len, alignment, ret_addr);
    }
    fn resize(raw: *anyopaque, memory: []u8, alignment: std.mem.Alignment, len: usize, ret_addr: usize) bool {
        const self: *Session = @ptrCast(@alignCast(raw));
        self.allocation_mutex.lockUncancelable(self.io);
        defer self.allocation_mutex.unlock(self.io);
        return self.parent.rawResize(memory, alignment, len, ret_addr);
    }
    fn remap(raw: *anyopaque, memory: []u8, alignment: std.mem.Alignment, len: usize, ret_addr: usize) ?[*]u8 {
        const self: *Session = @ptrCast(@alignCast(raw));
        self.allocation_mutex.lockUncancelable(self.io);
        defer self.allocation_mutex.unlock(self.io);
        return self.parent.rawRemap(memory, alignment, len, ret_addr);
    }
    fn free(raw: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *Session = @ptrCast(@alignCast(raw));
        self.allocation_mutex.lockUncancelable(self.io);
        defer self.allocation_mutex.unlock(self.io);
        self.parent.rawFree(memory, alignment, ret_addr);
    }
    fn enqueue(self: *Session, queue: *Queue, value: json.Owned) !void {
        const node = try self.allocator().create(Node);
        errdefer self.allocator().destroy(node);
        node.* = .{ .value = value };
        self.channel_mutex.lockUncancelable(self.io);
        defer self.channel_mutex.unlock(self.io);
        if (queue.count >= 100_016) return error.CodemodeWorkerQueueLimit;
        queue.append(node);
    }
    fn clear(self: *Session, queue: *Queue) void {
        while (queue.pop()) |node| {
            node.value.deinit();
            self.allocator().destroy(node);
        }
    }
    fn publish(self: *Session, value: json.Owned) !void {
        try self.enqueue(&self.events, value);
        self.owner_signal.notify(self.io);
        if (self.options.notify) |notify| notify(self.options.notify_context);
    }
    fn event(self: *Session, name: []const u8) !json.Owned {
        var result = try json.Owned.empty(self.allocator());
        errdefer result.deinit();
        result.value = .{ .object = .empty };
        try result.value.object.put(result.arena.allocator(), "type", .{ .string = name });
        return result;
    }
    fn started(raw: ?*anyopaque, _: *run_mod.Run, fingerprint: []const u8) !void {
        const self: *Session = @ptrCast(@alignCast(raw.?));
        var value = try self.event("started");
        errdefer value.deinit();
        const a = value.arena.allocator();
        try value.value.object.put(a, "fingerprint", .{ .string = try a.dupe(u8, fingerprint) });
        try self.publish(value);
    }
    fn called(raw: ?*anyopaque, _: *run_mod.Run, call: run_mod.Call) !void {
        const self: *Session = @ptrCast(@alignCast(raw.?));
        var value = try self.event("call");
        errdefer value.deinit();
        const a = value.arena.allocator();
        try value.value.object.put(a, "id", .{ .integer = @intCast(call.id) });
        try value.value.object.put(a, "target", .{ .string = @tagName(call.target) });
        try value.value.object.put(a, "name", .{ .string = try a.dupe(u8, call.name) });
        if (call.args) |args| try value.value.object.put(a, "args", try json.clone(a, args));
        try self.publish(value);
    }
    fn idle(raw: ?*anyopaque, _: *run_mod.Run, seq: f64, issued: f64) !void {
        const self: *Session = @ptrCast(@alignCast(raw.?));
        var value = try self.event("idle");
        errdefer value.deinit();
        const a = value.arena.allocator();
        try value.value.object.put(a, "seq", .{ .float = seq });
        try value.value.object.put(a, "issued", .{ .float = issued });
        try self.publish(value);
    }
    fn output(raw: ?*anyopaque, item: json.Value) !void {
        const self: *Session = @ptrCast(@alignCast(raw.?));
        var value = try self.event("output");
        errdefer value.deinit();
        try value.value.object.put(value.arena.allocator(), "item", try json.clone(value.arena.allocator(), item));
        try self.publish(value);
    }
    fn workerMain(self: *Session) void {
        self.execute() catch |failure| {
            self.failure = failure;
        };
        self.completed.store(true, .release);
        self.owner_signal.notify(self.io);
        if (self.options.notify) |notify| notify(self.options.notify_context);
    }
    fn execute(self: *Session) !void {
        const run = try run_mod.Run.create(self.allocator(), self.io, self.source, .{ .started_at = self.options.started_at, .seed = self.options.seed, .tools = self.options.tools, .globals = self.options.globals, .store = self.options.store, .timeout_ms = self.options.timeout_ms, .memory_limit = self.options.memory_limit, .stack_limit = self.options.stack_limit, .interrupt_budget = self.options.interrupt_budget, .abort_flag = &self.abort_requested, .observer = .{ .context = self, .started = started, .call = called, .idle = idle, .output = output } });
        var released = false;
        defer if (!released) run.deinit();
        try run.begin();
        while (!run.finished) {
            const observed = self.worker_signal.observe();
            var delivered = false;
            while (true) {
                self.channel_mutex.lockUncancelable(self.io);
                const node = self.commands.pop();
                self.channel_mutex.unlock(self.io);
                const command = node orelse break;
                defer {
                    command.value.deinit();
                    self.allocator().destroy(command);
                }
                const value = command.value.value;
                delivered = true;
                const payload = value.object.get("payload");
                try run.deliver(try json.asNumber(value.object.get("seq").?), try json.asNumber(value.object.get("now").?), @intCast(try json.asInteger(value.object.get("id").?)), if (value.object.get("ok").?.bool) .{ .success = if (payload) |bytes| bytes.string else null } else .{ .failure = .{ .message = payload.?.string, .properties = if (value.object.get("properties")) |bytes| bytes.string else null, .properties_was_object = value.object.get("propertiesWasObject").?.bool } });
            }
            if (@atomicLoad(bool, &self.abort_requested, .acquire)) try run.abort();
            if (delivered or run.core.checkLimits(false)) try run.pump();
            if (!run.finished) _ = try self.worker_signal.waitAfter(self.io, observed, .{ .duration = .{ .raw = .fromMilliseconds(5), .clock = .awake } });
        }
        var done = try self.event("done");
        errdefer done.deinit();
        try done.value.object.put(done.arena.allocator(), "result", try json.clone(done.arena.allocator(), run.core.result.value));
        // A terminal event means the C runtime has actually been released.
        run.deinit();
        released = true;
        try self.publish(done);
    }
};

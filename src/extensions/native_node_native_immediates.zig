//! Node v24.13 Environment::SetImmediate / RunAndClearNativeImmediates.
//! Selected owner-thread queue for native-only callback captures. The required
//! Hooks are native InternalCallbackScope/TriggerUncaughtException operations;
//! this component neither installs guest handlers nor substitutes JS Immediates.
const std = @import("std");
const em = @import("engine.zig");
const owned = @import("native_sdk_owned_completion.zig");
const c = em.c;

pub const Mode = enum { check, cleanup };
pub const CallbackScope = struct {
    raw: ?*anyopaque,
    // Consumes the actual callback-scope owner on both typed outcomes. Cleanup
    // mode must keep the real JS-disallow scope active through the whole drain.
    finish: *const fn (*em.Engine, ?*anyopaque, anyerror!bool) anyerror!bool,
};
pub const Hooks = struct {
    begin: *const fn (*em.Engine, Mode) anyerror!CallbackScope,
    // The real native uncaught-exception operation runs after destruction of
    // the callback. It consumes/handles the actual current exception or leaves
    // an actual termination/fatal event for the surrounding callback scope.
    // Source continues draining native callbacks after this operation.
    caught: *const fn (*em.Engine, anyerror) void,

    pub fn same(self: Hooks, other: Hooks) bool {
        return self.begin == other.begin and self.caught == other.caught;
    }
};

/// A producer allocates this ticket before entering GC-sensitive publication.
/// enqueue consumes it on every path. Captures and destroy must be native-only;
/// no JSValue, Engine entitlement, or unmarked VM root belongs to a ticket.
pub const Task = struct {
    next: ?*Task = null,
    queued: bool = false,
    refed: bool,
    // Borrowed during this call. It may enqueue another owned ticket, but must
    // not re-enqueue or destroy this consumed ticket: drain destroys it next.
    run: *const fn (*em.Engine, *Task) anyerror!void,
    destroy: *const fn (*Task) void,
};

pub const Queue = struct {
    memory_owner: *anyopaque,
    references: std.atomic.Value(usize) = .init(1),
    owner_thread: std.Thread.Id,
    engine: ?*em.Engine,
    hooks: Hooks,
    head: ?*Task = null,
    tail: ?*Task = null,
    count: usize = 0,
    refed_count: usize = 0,
    pumping: bool = false,
    closing: bool = false,

    /// Owned native result. The caller uses the canonical native allocation
    /// boundary before publication; this routine has no guest operation.
    pub fn create(engine: *em.Engine, hooks: Hooks) !*Queue {
        const memory_owner = engine.native_memory_owner;
        c.pi_js_retain_memory_owner(memory_owner);
        errdefer c.pi_js_release_memory_owner(memory_owner);
        if (c.pi_js_native_memory_reserve(memory_owner, @sizeOf(Queue)) == 0)
            return error.OutOfMemory;
        errdefer c.pi_js_native_memory_release(memory_owner, @sizeOf(Queue));
        const self = try std.heap.c_allocator.create(Queue);
        self.* = .{
            .memory_owner = memory_owner,
            .owner_thread = std.Thread.getCurrentId(),
            .engine = engine,
            .hooks = hooks,
        };
        return self;
    }
    pub fn retain(self: *Queue) *Queue {
        const old = self.references.fetchAdd(1, .monotonic);
        std.debug.assert(old != 0);
        return self;
    }
    pub fn release(self: *Queue) void {
        const old = self.references.fetchSub(1, .acq_rel);
        std.debug.assert(old != 0);
        if (old != 1) return;
        std.debug.assert(self.engine == null and self.head == null and
            self.tail == null and self.count == 0 and self.refed_count == 0 and
            !self.pumping);
        const memory_owner = self.memory_owner;
        std.heap.c_allocator.destroy(self);
        c.pi_js_native_memory_release(memory_owner, @sizeOf(Queue));
        c.pi_js_release_memory_owner(memory_owner);
    }
    fn assertOwner(self: *Queue) void {
        std.debug.assert(std.Thread.getCurrentId() == self.owner_thread);
    }
    pub fn pending(self: *const Queue) bool {
        return self.engine != null and self.count != 0;
    }
    pub fn referenced(self: *const Queue) bool {
        return self.engine != null and self.refed_count != 0;
    }
    /// No allocation or guest entry. Once disarmed, a late native finalizer
    /// only destroys the consumed ticket; it never touches a dead Engine.
    pub fn enqueue(self: *Queue, task: *Task) void {
        std.debug.assert(!task.queued and task.next == null);
        const engine = self.engine orelse {
            task.destroy(task);
            return;
        };
        self.assertOwner();
        task.queued = true;
        if (self.tail) |last| last.next = task else self.head = task;
        self.tail = task;
        self.count += 1;
        if (task.refed) self.refed_count += 1;
        em.Engine.notifyOwner(engine);
    }
    fn shift(self: *Queue) ?*Task {
        const first = self.head orelse return null;
        self.head = first.next;
        if (self.head == null) self.tail = null;
        first.next = null;
        first.queued = false;
        self.count -= 1;
        return first;
    }
    fn drainBody(self: *Queue, engine: *em.Engine, mode: Mode) bool {
        var removed_refed: usize = 0;
        // Source subtracts the drained ref count after the complete native
        // queue, before InternalCallbackScope's destructor/checkpoint.
        defer self.refed_count -= removed_refed;
        var worked = false;
        while (self.shift()) |task| {
            const is_refed = task.refed;
            if (is_refed) removed_refed += 1;
            const outcome: anyerror!void =
                if (mode == .check or is_refed) task.run(engine, task) else {};
            // Record actual failure before destroying native captures. This
            // is the Source head.reset() boundary before HasCaught/Trigger.
            var completion = owned.Completion.initVoid(engine, outcome);
            task.destroy(task);
            completion.finishVoid() catch |err| self.hooks.caught(engine, err);
            worked = true;
        }
        return worked;
    }
    fn inScope(self: *Queue, engine: *em.Engine, mode: Mode) !bool {
        const entered = try self.hooks.begin(engine, mode);
        return entered.finish(engine, entered.raw, self.drainBody(engine, mode));
    }
    pub fn drain(self: *Queue, engine: *em.Engine, mode: Mode) !bool {
        self.assertOwner();
        const current_engine = self.engine orelse return error.NativeImmediateQueueClosed;
        if (current_engine != engine) return error.NativeImmediateQueueWrongEngine;
        if (self.pumping) return false;
        _ = self.retain();
        defer self.release();
        self.pumping = true;
        defer self.pumping = false;
        // Keep the first actual native event across all callbacks even if an
        // uncaught operation terminates guest execution while native draining
        // continues. No event is inferred from a returned Error payload.
        var invocation: em.Engine.NativeInvocation = .{};
        engine.enterNativeInvocation(&invocation);
        var worked = false;
        const result: anyerror!void = if (self.inScope(engine, mode)) |value| blk: {
            worked = value;
            break :blk {};
        } else |err| err;
        var completion = owned.Completion.initVoid(engine, result);
        _ = engine.leaveNativeInvocation(&invocation, c.pi_js_undefined());
        try completion.finishVoid();
        return worked;
    }
    fn disarm(self: *Queue) void {
        // Clear access to the VM before destroying any remaining ticket.
        self.engine = null;
        while (self.shift()) |task| {
            if (task.refed) self.refed_count -= 1;
            task.destroy(task);
        }
        std.debug.assert(self.refed_count == 0);
    }
    /// Used only for a failed/unselected construction before publication.
    pub fn discardUnpublished(self: *Queue) void {
        self.assertOwner();
        std.debug.assert(self.head == null and !self.pumping);
        self.disarm();
        self.release();
    }
    /// The real cleanup scope forbids JS; only refed native callbacks execute.
    /// An entry/scope failure still disarms and retires every native ticket.
    /// External queue entitlements may then outlive both Engine and runtime.
    pub fn close(self: *Queue, engine: *em.Engine) !void {
        self.assertOwner();
        if (self.engine == null) return;
        if (self.closing or self.pumping) return error.NativeImmediateCloseDuringDrain;
        self.closing = true;
        defer self.disarm();
        _ = try self.drain(engine, .cleanup);
    }
};

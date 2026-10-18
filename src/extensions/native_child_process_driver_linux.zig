//! Actual Linux VM-owner/Hub bridge for reviewed pidfd ownership and epoll.
//! This is a private native admission API, not a synchronous Node spawn result.
//! Source public exec-status admission/ProcessWrap facade remains unselected.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const env = @import("native_env_io.zig");
const wake = @import("native_owner_wake.zig");
const waits = @import("native_child_process_epoll_linux.zig");
const io = @import("native_child_process_async_linux.zig");
const owned = @import("native_child_process_owned_linux.zig");
const spawn = @import("native_child_process_spawn_linux.zig");
const assembly = @import("native_child_process_linux.zig");
const options = @import("native_child_process_options.zig");
const Mutex = @import("native_child_process_linux_mutex.zig").Mutex;
pub const Event = union(enum) {
    launch: spawn.Status,
    stdout: io.Output, stderr: io.Output,
    write: io.WriteCompletion, endpoint: io.EndpointCompletion,
    input_finished: io.ShutdownCompletion,
    exit: @import("native_child_process_transport.zig").Result,
    failure: anyerror,
};
pub const Hooks = struct {
    context: *anyopaque,
    deliver: *const fn (*js.Engine, *anyopaque, *Driver, Event) anyerror!void,
    poll: ?*const fn (*js.Engine, *anyopaque, *Driver) anyerror!bool = null,
    stop: *const fn (*anyopaque) void,
    release: *const fn (*js.Engine, *anyopaque) void,
};
// Failed withdrawal/handoff cannot retain freed Engine-backed storage. These
// terminal native records retain the actual charged ticket/fds and/or lease,
// never an Engine, VM value, allocator, callback or std.Io backend pointer.
const Quarantine = struct { process: ?owned.Owned, lease: ?waits.Lease, failure: anyerror };
var quarantine_gate: Mutex = .{};
var quarantine: [16]?Quarantine = .{null} ** 16;
fn retainFailure(process: ?owned.Owned, lease: ?waits.Lease, failure: anyerror) void {
    quarantine_gate.lock(); defer quarantine_gate.unlock();
    for (&quarantine) |*slot| if (slot.* == null) { slot.* = .{ .process = process, .lease = lease, .failure = failure }; return; };
    // Both native ticket and readiness admission are globally capped at16. An
    // owner with either sole entitlement always has one remaining static slot.
    @panic("Linux native retirement cap invariant violated");
}
var controller_tag: u8 = 0;
pub const Controller = struct {
    hub: *env.Hub, wake_ref: wake.Ref,
    clients: [16]?*Driver = .{null} ** 16,
    cursor: usize = 0, stopping: bool = false, delivery_busy: bool = false,
    fn poll(raw: *anyopaque) !bool {
        const self: *Controller = @ptrCast(@alignCast(raw)); try self.hub.assertOwner();
        if (self.stopping or self.delivery_busy) return false;
        for (0..16) |offset| {
            const index = (self.cursor + offset) % 16;
            if (self.clients[index]) |client| if (try client.poll()) { self.cursor = (index + 1) % 16; return true; };
        }
        return false;
    }
    fn referenced(raw: *anyopaque) bool {
        const self: *Controller = @ptrCast(@alignCast(raw)); if (self.stopping) return false;
        for (self.clients) |client| if (client) |value| if (value.referenced or value.frame_index < value.frame_count or value.retire_requested) return true;
        return false;
    }
    fn bindHost(raw: *anyopaque, callback: *const fn (?*anyopaque) void, context: ?*anyopaque) void { const self: *Controller = @ptrCast(@alignCast(raw)); if (!self.stopping) wake.bindHost(self.wake_ref, callback, context); }
    fn detachHost(raw: *anyopaque) void { const self: *Controller = @ptrCast(@alignCast(raw)); wake.detachHost(self.wake_ref); }
    fn stop(raw: *anyopaque) void {
        const self: *Controller = @ptrCast(@alignCast(raw)); if (self.stopping) return;
        std.debug.assert(!self.delivery_busy); self.stopping = true;
        // The common Hub completion owner alone detaches the shared sink.
        for (self.clients) |client| if (client) |value| value.stopNative();
    }
    fn stopped(raw: *anyopaque) void {
        const self: *Controller = @ptrCast(@alignCast(raw));
        for (&self.clients) |*client| if (client.*) |value| { client.* = null; value.releaseOwner(); };
        wake.release(self.wake_ref); self.hub.engine.gpa.destroy(self);
    }
};
fn controller(engine: *js.Engine) !*Controller {
    if (@import("builtin").os.tag != .linux) return error.RequiredLinuxChildReadiness;
    const hub = try env.get(engine); try hub.assertOwner(); if (hub.stopping) return error.NativeEnvClosed;
    for (hub.resources.items) |resource| if (resource.tag == @as(?*const anyopaque, &controller_tag)) return @ptrCast(@alignCast(resource.raw));
    const reference = try @import("native_owner_completion.zig").acquireNativeWake(engine);
    errdefer wake.release(reference);
    const self = try engine.gpa.create(Controller); errdefer engine.gpa.destroy(self);
    self.* = .{ .hub = hub, .wake_ref = reference };
    try hub.addResource(.{ .raw = self, .tag = &controller_tag, .poll = Controller.poll, .referenced = Controller.referenced, .stop = Controller.stop, .stopped = Controller.stopped });
    return self;
}
pub const acquireNativeWake = @import("native_owner_completion.zig").acquireNativeWake;
const Prepared = struct {
    control: *Controller, lease: waits.Lease, driver: *Driver, roots: []c.JSValue,
    fn discard(self: Prepared) void {
        const engine = self.control.hub.engine;
        waits.releaseAfterWithdraw(self.lease) catch |failure| retainFailure(null, self.lease, failure);
        for (self.roots) |value| engine.freeValue(value);
        engine.gpa.free(self.roots); engine.gpa.destroy(self.driver);
    }
    fn commit(self: Prepared, actual: *owned.Owned, hooks: Hooks) *Driver {
        self.driver.* = .{ .control = self.control, .lease = self.lease, .transport = io.Transport.take(actual), .hooks = hooks, .roots = self.roots };
        self.control.clients[self.lease.slot] = self.driver; waits.requestStep(self.lease); return self.driver;
    }
};
fn prepare(engine: *js.Engine, roots: []const c.JSValue) !Prepared {
    if (roots.len > 16) return error.NativeChildOwnerRootLimit;
    const control = try controller(engine);
    const self = try engine.gpa.create(Driver); errdefer engine.gpa.destroy(self);
    const values = try engine.gpa.alloc(c.JSValue, roots.len); errdefer engine.gpa.free(values);
    for (roots, values) |value, *slot| slot.* = c.JS_DupValue(engine.context, value);
    errdefer for (values) |value| engine.freeValue(value);
    const lease = try waits.reserve(control.wake_ref);
    return .{ .control = control, .lease = lease, .driver = self, .roots = values };
}
pub const Admission = union(enum) {
    pending: *Driver,
    // The real native child and original owner-thread saved mask are retained.
    // The host MUST recover immediately or enter its fatal stop boundary before
    // resuming VM work. This is never a public spawn result or catchable UV errno.
    parent_mask_recovery_required: *Driver,
};
pub const NativeRetirement = enum { native_reaper, native_quarantine };
pub const Driver = struct {
    control: *Controller, lease: waits.Lease, transport: io.Transport,
    hooks: Hooks, roots: []c.JSValue,
    owned_config: ?options.Config = null,
    demand: io.Demand = .{ .stdout = false, .stderr = false }, referenced: bool = true,
    frame: [10]Event = undefined, frame_count: usize = 0, frame_index: usize = 0,
    frame_resubmit: bool = false, stopped: bool = false, delivery_busy: bool = false,
    retire_requested: bool = false, scheduler_failed: bool = false,
    stop_retirement: ?NativeRetirement = null,
    /// Moves caller's actual native ticket/endpoints ONLY on success. Every
    /// allocation/reservation precedes that move. Hooks context ownership also
    /// transfers only on success; an error leaves the caller's sole entitlement.
    /// Parent signal-mask recovery must already be resolved on the exact owner.
    pub fn adopt(engine: *js.Engine, actual: *owned.Owned, hooks: Hooks, roots: []const c.JSValue) !*Driver {
        if (actual.detached or !actual.ticket.charged or actual.ticket.watch.owner != std.Thread.getCurrentId()) return error.NativeLinuxChildTicketOwnerThreadRequired;
        if (actual.ticket.watch.epoll != null) return error.NativeChildPidfdRetirementAcknowledgementRequired;
        if (actual.ticket.parent_mask_restore_errno != null) return error.NativeLinuxChildParentMaskRecoveryRequired;
        const prepared = try prepare(engine, roots);
        return prepared.commit(actual, hooks);
    }
    /// Genuine factory transaction. Takes Config on every return; Hooks context
    /// transfers only when a real child ticket returns. Recovery remains caller
    /// owned across a failed clone+failed mask restore (there is then no child).
    /// All bridge/VM roots/readiness admission precedes clone; after a real child
    /// returns, commit cannot allocate/fail or drop the sole native entitlement.
    pub fn create(engine: *js.Engine, config: options.Config, hooks: Hooks, roots: []const c.JSValue, recovery: *spawn.MaskRecovery) !Admission {
        var owned_config = config; var config_owned = true;
        defer if (config_owned) owned_config.deinit();
        const prepared = try prepare(engine, roots); var prepared_owned = true;
        defer if (prepared_owned) prepared.discard();
        const actual = try assembly.create(engine.gpa, owned_config.argv.items, owned_config.cwd, &owned_config.environment, owned_config.options, recovery);
        var native = owned.Owned.adopt(actual);
        const driver = prepared.commit(&native, hooks); prepared_owned = false;
        driver.owned_config = owned_config; config_owned = false;
        return if (driver.transport.process.ticket.parent_mask_restore_errno != null) .{ .parent_mask_recovery_required = driver } else .{ .pending = driver };
    }
    pub fn restoreParentMask(self: *Driver) !void { try self.guard(); try self.transport.process.restoreParentMask(); waits.requestStep(self.lease); }
    /// Native admission failed/was cancelled before any callback frame became
    /// publicly visible. Stops only the exact pidfd, transfers native ownership,
    /// then releases host roots. Return is never independent process absence.
    /// Success consumes this Driver pointer; failure leaves caller ownership.
    pub fn retireUncertainAdmission(self: *Driver) !NativeRetirement {
        try self.guard();
        if (self.transport.process.ticket.parent_mask_restore_errno != null) return error.NativeLinuxChildParentMaskRecoveryRequired;
        if (self.delivery_busy or self.control.delivery_busy or self.frame_count != 0) return error.NativeLinuxAdmissionAlreadyDelivering;
        self.retireNative(true);
        const retirement = self.stop_retirement orelse unreachable;
        self.control.clients[self.lease.slot] = null;
        self.releaseOwner(); return retirement;
    }
    fn guard(self: *Driver) !void { try self.control.hub.assertOwner(); if (self.stopped or self.control.stopping) return error.NativeChildOwnerRetired; }
    fn mutate(self: *Driver) !void { try self.guard(); try waits.withdraw(self.lease); }
    pub fn beginChunk(self: *Driver, data: []const u8, token: u64) !void { try self.mutate(); defer waits.requestStep(self.lease); try self.transport.beginChunk(data, token); }
    pub fn finishInput(self: *Driver) !void { try self.mutate(); defer waits.requestStep(self.lease); try self.transport.finishInput(); }
    pub fn closeInput(self: *Driver) !void { try self.mutate(); self.transport.closeInput(); waits.requestStep(self.lease); }
    pub fn destroyOutput(self: *Driver, index: usize) !void { try self.mutate(); defer waits.requestStep(self.lease); try self.transport.destroyOutput(index); }
    pub fn setDemand(self: *Driver, demand: io.Demand) !void { try self.mutate(); self.demand = demand; waits.requestStep(self.lease); }
    pub fn signalNumber(self: *Driver, number: i32) !bool { try self.guard(); return self.transport.process.signalNumber(number); }
    pub fn setReferenced(self: *Driver, value: bool) !void { try self.guard(); self.referenced = value; wake.notify(self.control.wake_ref); }
    pub fn requestRetire(self: *Driver) !void { try self.guard(); self.retire_requested = true; waits.requestStep(self.lease); }
    fn append(self: *Driver, event: Event) void { std.debug.assert(self.frame_count < self.frame.len); self.frame[self.frame_count] = event; self.frame_count += 1; }
    fn failNative(self: *Driver, failure: anyerror) bool {
        if (self.scheduler_failed) return false;
        self.scheduler_failed = true;
        self.append(.{ .failure = failure }); waits.requestStep(self.lease); return true;
    }
    fn poll(self: *Driver) !bool {
        if (self.stopped or self.delivery_busy or self.control.delivery_busy) return false;
        if (self.transport.process.ticket.parent_mask_restore_errno != null) return error.NativeLinuxChildParentMaskRecoveryRequired;
        const engine = self.control.hub.engine;
        if (self.frame_index < self.frame_count) {
            self.delivery_busy = true; self.control.delivery_busy = true;
            defer { self.delivery_busy = false; self.control.delivery_busy = false; }
            const event = self.frame[self.frame_index]; self.frame_index += 1;
            defer if (self.frame_index == self.frame_count) { self.frame_index = 0; self.frame_count = 0; waits.requestStep(self.lease); };
            engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
            try self.hooks.deliver(engine, self.hooks.context, self, event); return true;
        }
        if (self.hooks.poll) |owner_poll| {
            self.delivery_busy = true; self.control.delivery_busy = true;
            defer { self.delivery_busy = false; self.control.delivery_busy = false; }
            engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
            if (try owner_poll(engine, self.hooks.context, self)) return true;
        }
        if (self.scheduler_failed) {
            if (!self.retire_requested) return false;
            // Explicit failure retirement transfers native ownership without a
            // new public/physical signal. Hub shutdown has its own force policy.
            self.retireNative(false);
            self.control.clients[self.lease.slot] = null; self.releaseOwner(); return true;
        }
        const ready = waits.takeReady(self.lease) orelse return false;
        if (ready.failure) |failure| return self.failNative(failure);
        waits.withdraw(self.lease) catch |failure| return self.failNative(failure);
        const result = self.transport.stepAfterWithdraw(self.demand) catch |failure| return self.failNative(failure);
        if (result.launch) |status| self.append(.{ .launch = status });
        if (self.transport.takeWriteCompletion()) |completion| self.append(.{ .write = completion });
        while (self.transport.takeEndpointCompletion()) |completion| self.append(.{ .endpoint = completion });
        if (result.input_finished) |completion| self.append(.{ .input_finished = completion });
        switch (result.stdout) { .none => {}, else => self.append(.{ .stdout = result.stdout }) }
        switch (result.stderr) { .none => {}, else => self.append(.{ .stderr = result.stderr }) }
        if (result.child_exit) |exit| self.append(.{ .exit = exit });
        self.frame_resubmit = result.resubmit.stdin or result.resubmit.stdout or result.resubmit.stderr;
        if (self.retire_requested and self.frame_count == 0 and self.transport.canDispose()) {
            self.transport.disposeAfterWithdraw() catch |failure| return self.failNative(failure);
            waits.releaseAfterWithdraw(self.lease) catch |failure| retainFailure(null, self.lease, failure);
            self.control.clients[self.lease.slot] = null; self.releaseOwner(); return true;
        }
        const snapshot = self.transport.snapshot(self.demand, null) catch |failure| return self.failNative(failure);
        waits.publish(self.lease, snapshot) catch |failure| return self.failNative(failure);
        if (self.frame_count != 0 or self.frame_resubmit) waits.requestStep(self.lease);
        return true;
    }
    fn stopNative(self: *Driver) void { self.retireNative(true); }
    fn retireNative(self: *Driver, force: bool) void {
        if (self.stopped) return; self.stopped = true;
        std.debug.assert(!self.delivery_busy); self.hooks.stop(self.hooks.context);
        // Exact pidfd only. No numeric PID, unrelated child or descendant walk.
        if (force) _ = self.transport.process.signalNumber(9) catch false;
        waits.withdraw(self.lease) catch |failure| { self.quarantineNative(failure); return; };
        const admission = self.transport.detachToReaperAfterWithdraw() catch |failure| { self.quarantineNative(failure); return; };
        self.stop_retirement = if (admission == .queued) .native_reaper else .native_quarantine;
        waits.releaseAfterWithdraw(self.lease) catch |failure| { retainFailure(null, self.lease, failure); self.stop_retirement = .native_quarantine; };
    }
    fn quarantineNative(self: *Driver, failure: anyerror) void {
        retainFailure(self.transport.process, self.lease, failure);
        self.transport.process.detached = true;
        self.transport.process.ticket.charged = false;
        self.transport.process.ticket.watch.pidfd = null;
        self.transport.process.ticket.exec_status_fd = null;
        self.transport.process.endpoints = .{null} ** 3;
        self.transport.disposed = true;
        self.stop_retirement = .native_quarantine;
    }
    fn releaseOwner(self: *Driver) void {
        const engine = self.control.hub.engine; self.hooks.release(engine, self.hooks.context);
        for (self.roots) |value| engine.freeValue(value); engine.gpa.free(self.roots);
        if (self.owned_config) |*config| config.deinit();
        engine.gpa.destroy(self);
    }
};

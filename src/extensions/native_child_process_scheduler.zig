//! Owner-thread child driver plus process-lifetime native readiness service.
//! Public piped child binding still requires the genuine canonical Socket port.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const c = js.c;
const env = @import("native_env_io.zig");
const wake = @import("native_owner_wake.zig");
const waits = @import("native_child_process_wait_registry.zig");
const async_io = @import("native_child_process_async_transport.zig");
const options = @import("native_child_process_options.zig");
const clock = @import("native_child_process_stdin_windows.zig");
const shutdown = @import("native_child_process_shutdown_windows.zig");
pub const Event = union(enum) {
    stdout: async_io.Output, stderr: async_io.Output,
    write: async_io.WriteCompletion, endpoint: async_io.EndpointCompletion,
    exit: @import("native_child_process_transport.zig").Result,
    timeout_signal: bool, timeout_failure: anyerror, failure: anyerror,
};
pub const Hooks = struct {
    context: *anyopaque,
    // Actual VM/provider entry only here, on the owner and outside native locks.
    deliver: *const fn (*js.Engine, *anyopaque, *OwnerBridge, Event) anyerror!void,
    // One owner callback for terminal endpoint state already observed before a
    // later stream request. It must report false when its bounded queue is empty.
    poll: ?*const fn (*js.Engine, *anyopaque, *OwnerBridge) anyerror!bool = null,
    stop: *const fn (*anyopaque) void,
    release: *const fn (*js.Engine, *anyopaque) void,
};
var controller_tag: u8 = 0;
pub const Controller = struct {
    hub: *env.Hub, wake_ref: wake.Ref,
    clients: [16]?*OwnerBridge = .{null} ** 16,
    cursor: usize = 0, stopping: bool = false, delivery_busy: bool = false,
    fn poll(raw: *anyopaque) !bool {
        const self: *Controller = @ptrCast(@alignCast(raw));
        try self.hub.assertOwner();
        if (self.stopping or self.delivery_busy) return false;
        for (0..16) |offset| {
            const index = (self.cursor + offset) % 16;
            const client = self.clients[index] orelse continue;
            if (try client.poll()) { self.cursor = (index + 1) % 16; return true; }
        }
        return false;
    }
    fn referenced(raw: *anyopaque) bool {
        const self: *Controller = @ptrCast(@alignCast(raw));
        if (self.stopping) return false;
        // Native-observed callback frames and exact retirement acknowledgements
        // are runnable/closing work even after the last public handle is unref'd.
        for (self.clients) |client| if (client) |value| if (value.referenced or value.frame_index < value.frame_count or value.retiring) return true;
        return false;
    }
    fn bindHost(raw: *anyopaque, publish: *const fn (?*anyopaque) void, context: ?*anyopaque) void {
        const self: *Controller = @ptrCast(@alignCast(raw));
        if (!self.stopping) wake.bindHost(self.wake_ref, publish, context);
    }
    fn detachHost(raw: *anyopaque) void { const self: *Controller = @ptrCast(@alignCast(raw)); wake.detachHost(self.wake_ref); }
    fn stop(raw: *anyopaque) void {
        const self: *Controller = @ptrCast(@alignCast(raw));
        if (self.stopping) return;
        std.debug.assert(!self.delivery_busy);
        self.stopping = true;
        // The common Hub completion owner alone detaches the shared sink.
        for (self.clients) |client| if (client) |value| value.stopNative();
    }
    fn stopped(raw: *anyopaque) void {
        const self: *Controller = @ptrCast(@alignCast(raw));
        for (&self.clients) |*client| if (client.*) |value| { client.* = null; value.releaseOwner(); };
        wake.release(self.wake_ref);
        self.hub.engine.gpa.destroy(self);
    }
};
fn controller(engine: *js.Engine) !*Controller {
    const hub = try env.get(engine);
    try hub.assertOwner();
    if (hub.stopping) return error.NativeEnvClosed;
    for (hub.resources.items) |resource| if (resource.tag == &controller_tag) {
        const existing: *Controller = @ptrCast(@alignCast(resource.raw));
        if (existing.hub != hub) return error.NativeChildControllerOwnerMismatch;
        return existing;
    };
    const reference = try @import("native_owner_completion.zig").acquireNativeWake(engine);
    errdefer wake.release(reference);
    const self = try engine.gpa.create(Controller);
    errdefer engine.gpa.destroy(self);
    self.* = .{ .hub = hub, .wake_ref = reference };
    try hub.addResource(.{ .raw = self, .tag = &controller_tag, .poll = Controller.poll, .referenced = Controller.referenced, .stop = Controller.stop, .stopped = Controller.stopped });
    return self;
}
/// Caller owns this native reference. Close packets retain an independent copy,
/// publish atomic done, notify, then release without any Engine/Task pointer.
pub const acquireNativeWake = @import("native_owner_completion.zig").acquireNativeWake;
pub const OwnerBridge = struct {
    control: *Controller, lease: waits.Lease, transport: async_io.AsyncTransport,
    config: options.Config, hooks: Hooks, roots: []c.JSValue,
    demand: async_io.Demand = .{}, referenced: bool = true,
    frame: [8]Event = undefined, frame_count: usize = 0, frame_index: usize = 0,
    frame_resubmit: bool = false, delivery_busy: bool = false,
    retiring: bool = false, stopped: bool = false, retire_requested: bool = false,
    cleanup_failure: ?anyerror = null, timeout_at: ?u64 = null, timeout_sent: bool = false,
    retire_after_frame: bool = false,
    scheduler_failed: bool = false,

    pub const FailedAdmission = struct {
        control: *Controller, lease: waits.Lease,
        config: options.Config, roots: []c.JSValue,
        endpoints: @import("native_child_process_windows.zig").Failed,
        shutdown_ticket: ?shutdown.Ticket,
        /// Only before Socket/read operations attach. The exact real endpoints
        /// remain owned throughout rollback; there is no Process/PID to kill.
        pub fn releaseUnattached(self: *FailedAdmission, engine: *js.Engine) void {
            if (self.shutdown_ticket) |ticket| { shutdown.releaseUnassociated(ticket) catch {}; }
            if (self.endpoints.input_slot) |slot| { _ = slot.retire(); }
            for (self.endpoints.output_slots) |maybe_slot| if (maybe_slot) |slot| { _ = slot.retire(); };
            waits.detachForShutdown(self.lease, null);
            for (self.roots) |value| engine.freeValue(value);
            engine.gpa.free(self.roots); self.config.deinit();
            self.* = undefined;
        }
    };
    pub const Attempt = union(enum) { running: *OwnerBridge, failed: FailedAdmission };
    /// Public prospective launch path. The old start entry is preserved. Both
    /// results retain actual owned state; a failed attempt never contains a
    /// placeholder native Process or process-wait handle.
    pub fn startAttempt(engine: *js.Engine, config: options.Config, hooks: Hooks, roots: []const c.JSValue) !Attempt {
        var owned_config = config; var config_owned = true;
        defer if (config_owned) owned_config.deinit();
        if (builtin.os.tag != .windows) return error.RequiredNativePosixChildReadiness;
        if (roots.len > 16) return error.NativeChildOwnerRootLimit;
        const control = try controller(engine);
        const lease = try waits.reserve(control.wake_ref);
        var lease_owned = true; errdefer if (lease_owned) waits.detachForShutdown(lease, null);
        var shutdown_ticket: ?shutdown.Ticket = if (owned_config.options.stdio[0] == .pipe) try shutdown.reserve(control.wake_ref, lease) else null;
        errdefer if (shutdown_ticket) |ticket| shutdown.releaseUnassociated(ticket) catch {};
        const owned_roots = try engine.gpa.alloc(c.JSValue, roots.len);
        for (roots, owned_roots) |value, *slot| slot.* = c.JS_DupValue(engine.context, value);
        var roots_owned = true;
        errdefer if (roots_owned) { for (owned_roots) |value| engine.freeValue(value); engine.gpa.free(owned_roots); };
        var native_options = owned_config.options; native_options.windows_overlapped_output = true;
        const attempt = try @import("native_child_process_windows.zig").spawnAttempt(engine.gpa, owned_config.argv.items, owned_config.cwd, &owned_config.environment, native_options);
        switch (attempt) {
            .failed => |endpoints| {
                const retained_shutdown = shutdown_ticket; shutdown_ticket = null;
                lease_owned = false; config_owned = false; roots_owned = false;
                return .{ .failed = .{ .control = control, .lease = lease, .config = owned_config, .roots = owned_roots, .endpoints = endpoints, .shutdown_ticket = retained_shutdown } };
            },
            .spawned => |spawned| {
                const process = @import("native_child_process_transport.zig").Process.adoptWindowsSpawned(control.hub.io, spawned);
                var transport: async_io.AsyncTransport = .{ .process = process, .input_closed = native_options.stdio[0] != .pipe, .output_closed = .{ native_options.stdio[1] != .pipe, native_options.stdio[2] != .pipe }, .strict_endpoint_retirement = true };
                var transport_owned = true;
                errdefer if (transport_owned) { const native_process = transport.detachForShutdown() catch null; waits.detachForShutdown(lease, native_process); lease_owned = false; };
                if (shutdown_ticket) |ticket| { try transport.attachWindowsShutdown(ticket); shutdown_ticket = null; }
                try waits.attachProcess(lease, transport.process.child.id.?);
                const self = try engine.gpa.create(OwnerBridge);
                self.* = .{ .control = control, .lease = lease, .transport = transport, .config = owned_config, .hooks = hooks, .roots = owned_roots, .timeout_at = if (owned_config.timeout_ms) |timeout| clock.monotonicMilliseconds() +| timeout else null };
                control.clients[lease.slot] = self;
                lease_owned = false; transport_owned = false; config_owned = false; roots_owned = false;
                waits.requestStep(lease); return .{ .running = self };
            },
        }
    }

    /// Takes config ownership on both success and failure. Hooks/root values are
    /// actual provider state; this native API does not manufacture a Socket.
    pub fn start(engine: *js.Engine, config: options.Config, hooks: Hooks, roots: []const c.JSValue) !*OwnerBridge {
        var owned_config = config;
        var config_owned = true;
        defer if (config_owned) owned_config.deinit();
        if (builtin.os.tag != .windows) return error.RequiredNativePosixChildReadiness;
        if (roots.len > 16) return error.NativeChildOwnerRootLimit;
        const control = try controller(engine);
        const lease = try waits.reserve(control.wake_ref);
        var lease_owned = true;
        errdefer if (lease_owned) waits.detachForShutdown(lease, null);
        // All native shutdown refs/workers/tickets precede pipe creation. No
        // attached-only wake retain is attempted from Engine teardown.
        var shutdown_ticket: ?shutdown.Ticket = if (owned_config.options.stdio[0] == .pipe) try shutdown.reserve(control.wake_ref, lease) else null;
        errdefer if (shutdown_ticket) |ticket| shutdown.releaseUnassociated(ticket) catch {};
        const owned_roots = try engine.gpa.alloc(c.JSValue, roots.len);
        for (roots, owned_roots) |value, *slot| slot.* = c.JS_DupValue(engine.context, value);
        var roots_owned = true;
        errdefer if (roots_owned) { for (owned_roots) |value| engine.freeValue(value); engine.gpa.free(owned_roots); };
        var transport = try async_io.AsyncTransport.init(control.hub.io, engine.gpa, owned_config.argv.items, owned_config.cwd, &owned_config.environment, owned_config.options);
        var transport_owned = true;
        errdefer if (transport_owned) { const native_process = transport.detachForShutdown() catch null; waits.detachForShutdown(lease, native_process); lease_owned = false; };
        transport.strict_endpoint_retirement = true;
        if (shutdown_ticket) |ticket| { try transport.attachWindowsShutdown(ticket); shutdown_ticket = null; }
        try waits.attachProcess(lease, transport.process.child.id.?);
        const self = try engine.gpa.create(OwnerBridge);
        self.* = .{ .control = control, .lease = lease, .transport = transport, .config = owned_config, .hooks = hooks, .roots = owned_roots, .timeout_at = if (owned_config.timeout_ms) |timeout| clock.monotonicMilliseconds() +| timeout else null };
        control.clients[lease.slot] = self;
        lease_owned = false; transport_owned = false; config_owned = false; roots_owned = false;
        waits.requestStep(lease);
        return self;
    }
    fn guard(self: *OwnerBridge) !void {
        try self.control.hub.assertOwner();
        if (self.stopped or self.control.stopping or self.retiring) return error.NativeChildOwnerRetired;
    }
    fn mutate(self: *OwnerBridge) !void { try self.guard(); try waits.withdraw(self.lease); }
    // Once withdrawal succeeds, synchronous validation failures must still rearm
    // every unaffected pipe/process interest at the next owner checkpoint.
    pub fn beginChunk(self: *OwnerBridge, bytes: []const u8, token: u64) !void { try self.mutate(); defer waits.requestStep(self.lease); try self.transport.beginChunk(bytes, token); }
    pub fn finishInput(self: *OwnerBridge) !void { try self.mutate(); defer waits.requestStep(self.lease); try self.transport.finishInput(); }
    pub fn closeInput(self: *OwnerBridge) !void { try self.mutate(); self.transport.closeInput(); waits.requestStep(self.lease); }
    pub fn destroyOutput(self: *OwnerBridge, stream: @import("native_child_process_transport.zig").Stream) !void { try self.mutate(); self.transport.destroyOutput(stream); waits.requestStep(self.lease); }
    pub fn setDemand(self: *OwnerBridge, demand: async_io.Demand) !void { try self.mutate(); self.demand = demand; waits.requestStep(self.lease); }
    /// Source kill/ref/unref results are synchronous, never queued approximations.
    pub fn signal(self: *OwnerBridge, force: bool) !bool { try self.guard(); return self.transport.signal(force); }
    pub fn signalNumber(self: *OwnerBridge, number: i32) !bool { try self.guard(); return self.transport.process.signalNumber(number); }
    pub fn setReferenced(self: *OwnerBridge, value: bool) !void { try self.guard(); self.referenced = value; wake.notify(self.control.wake_ref); }
    pub fn requestRetire(self: *OwnerBridge) !void { try self.guard(); self.retire_requested = true; waits.requestStep(self.lease); }
    pub fn requestOwnerCheckpoint(self: *OwnerBridge) !void { try self.guard(); waits.requestStep(self.lease); }
    fn append(self: *OwnerBridge, event: Event) void { std.debug.assert(self.frame_count < self.frame.len); self.frame[self.frame_count] = event; self.frame_count += 1; }
    fn publish(self: *OwnerBridge) !void {
        var snapshot = try self.transport.watchSnapshot();
        if (!self.timeout_sent) if (self.timeout_at) |due| snapshot.deadline_ms = if (snapshot.deadline_ms) |prior| @min(prior, due) else due;
        try waits.publish(self.lease, snapshot);
    }
    fn canDispose(self: *OwnerBridge) bool {
        if (!self.transport.process.exited or !self.transport.input_closed or !self.transport.output_closed[0] or !self.transport.output_closed[1] or self.transport.token != null or self.transport.write_completion != null) return false;
        for (self.transport.endpoint_completion) |record| if (record != null) return false;
        return true;
    }
    fn poll(self: *OwnerBridge) !bool {
        if (self.stopped or self.delivery_busy or self.control.delivery_busy) return false;
        const engine = self.control.hub.engine;
        if (self.frame_count == 0) if (self.hooks.poll) |owner_poll| {
            self.delivery_busy = true; self.control.delivery_busy = true;
            defer { self.delivery_busy = false; self.control.delivery_busy = false; }
            engine.native_exception_diagnostics_suppressed += 1;
            defer engine.native_exception_diagnostics_suppressed -= 1;
            if (try owner_poll(engine, self.hooks.context, self)) return true;
        };
        if (self.frame_index < self.frame_count) {
            self.delivery_busy = true; self.control.delivery_busy = true;
            defer { self.delivery_busy = false; self.control.delivery_busy = false; }
            const event = self.frame[self.frame_index];
            self.frame_index += 1; // a throwing callback is never invoked twice
            engine.native_exception_diagnostics_suppressed += 1;
            defer engine.native_exception_diagnostics_suppressed -= 1;
            defer if (self.frame_index == self.frame_count) {
                self.frame_count = 0; self.frame_index = 0;
                if (self.retire_after_frame) {
                    self.retiring = true;
                    waits.retireObserved(self.lease) catch |err| { self.cleanup_failure = err; };
                } else if (self.frame_resubmit or self.retire_requested) waits.requestStep(self.lease);
            };
            try self.hooks.deliver(engine, self.hooks.context, self, event);
            return true;
        }
        const ready = waits.takeReady(self.lease) orelse return false;
        if (ready.mask.retired) {
            const released = waits.releaseRetired(self.lease);
            if (!released) return error.NativeChildRetirementAcknowledgementRequired;
            self.control.clients[self.lease.slot] = null;
            self.releaseOwner();
            return true;
        }
        if (self.retiring) return false;
        if (ready.failure) |failure| {
            if (self.scheduler_failed) return false;
            self.scheduler_failed = true;
            self.frame_resubmit = false;
            self.append(.{ .failure = failure });
            waits.requestStep(self.lease);
            return true;
        }
        if (self.scheduler_failed) return false;
        // Withdraw BEFORE step or any pending operation can reset/retire/reuse.
        try waits.withdraw(self.lease);
        if (!self.timeout_sent) if (self.timeout_at) |due| if (due <= clock.monotonicMilliseconds()) {
            self.timeout_sent = true;
            if (self.transport.process.signalNumber(self.config.kill_number)) |sent| self.append(.{ .timeout_signal = sent }) else |failure| self.append(.{ .timeout_failure = failure });
        };
        const result = try self.transport.step(self.demand);
        if (self.transport.takeWriteCompletion()) |completion| self.append(.{ .write = completion });
        while (self.transport.takeEndpointCompletion()) |completion| self.append(.{ .endpoint = completion });
        switch (result.stdout) { .none => {}, else => self.append(.{ .stdout = result.stdout }) }
        switch (result.stderr) { .none => {}, else => self.append(.{ .stderr = result.stderr }) }
        if (result.child_exit) |exit| self.append(.{ .exit = exit });
        self.frame_resubmit = result.resubmit.stdin or result.resubmit.stdout or result.resubmit.stderr;
        if (self.retire_requested and self.frame_count == 0 and self.canDispose()) {
            self.transport.disposeExited() catch |err| {
                self.cleanup_failure = err;
                self.append(.{ .failure = err });
                self.retire_after_frame = true;
                try self.publish();
                waits.requestStep(self.lease);
                return true;
            };
            self.retiring = true;
            try waits.retireObserved(self.lease);
            return true;
        }
        try self.publish();
        if (self.frame_count != 0 or self.frame_resubmit) waits.requestStep(self.lease);
        return true;
    }
    fn stopNative(self: *OwnerBridge) void {
        if (self.stopped) return;
        std.debug.assert(!self.delivery_busy);
        self.stopped = true;
        waits.withdraw(self.lease) catch {};
        self.hooks.stop(self.hooks.context);
        const native_process = self.transport.detachForShutdown() catch null;
        waits.detachForShutdown(self.lease, native_process);
    }
    fn releaseOwner(self: *OwnerBridge) void {
        const engine = self.control.hub.engine;
        self.hooks.release(engine, self.hooks.context);
        for (self.roots) |value| engine.freeValue(value);
        engine.gpa.free(self.roots);
        self.config.deinit();
        engine.gpa.destroy(self);
    }
};

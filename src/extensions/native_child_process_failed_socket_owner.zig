//! Genuine Socket/Hub owner for failed CreateProcess endpoints. No child process
//! or exit event is invented; public error/flush/close policy enables delivery.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const env = @import("native_env_io.zig");
const scheduler = @import("native_child_process_scheduler.zig");
const waits = @import("native_child_process_wait_registry.zig");
const wake = @import("native_owner_wake.zig");
const native = @import("native_child_process_failed_endpoints_windows.zig");
const socket = @import("native_node_net_socket.zig");
const pipes = @import("native_child_process_socket_owner.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const pipe_record = @import("native_child_process_pipe_record.zig");
pub const Hooks = struct {
    context: *anyopaque,
    release: *const fn (*js.Engine, *anyopaque) void,
};
const Event = union(enum) { stdout: native.Output, stderr: native.Output, write: native.Write, endpoint: native.Endpoint };
const Endpoint = struct {
    owner: *Owner, index: usize, referenced: bool = true,
    acknowledged: bool = false, write_pending: bool = false,
    final_token: ?u64 = null, destroy_token: ?u64 = null,
    close_failure: ?anyerror = null, retirement_pending: bool = false,
    record: ?pipe_record.Owned = null,
    fn from(raw: *anyopaque) *Endpoint { return @ptrCast(@alignCast(raw)); }
    fn hooks(self: *Endpoint) socket.Hooks { return .{ .context = self, .retain = retain, .release = release, .abandon = abandon, .read = read, .write = write, .finish = finish, .destroy = destroy, .referenced = reference, .error_value = errorValue }; }
    fn retain(raw: *anyopaque) void { from(raw).owner.references += 1; }
    fn release(raw: *anyopaque) void { from(raw).owner.releaseReference(); }
    fn closeRecord(raw: *anyopaque) !void {
        const self = from(raw); if (self.acknowledged) return;
        try self.owner.mutate(); defer waits.requestStep(self.owner.admission.lease);
        if (self.index == 0) self.owner.native_owner.closeInput() else try self.owner.native_owner.destroyOutput(self.index - 1);
    }
    fn recordHooks(raw: *anyopaque) !socket.Hooks { return from(raw).hooks(); }
    fn socketCreated(raw: *anyopaque, actual: *const socket.Owned) !void {
        const self = from(raw); try self.owner.guard();
        if (self.owner.hub.engine != actual.engine) return error.NativeChildSocketProviderOwnerMismatch;
        if (self.owner.sockets[self.index]) |*previous| previous.deinit();
        self.owner.sockets[self.index] = actual.clone();
    }
    fn abandon(raw: *anyopaque) void {
        const self = from(raw); if (self.owner.stopped) return;
        self.owner.mutate() catch return;
        if (self.index == 0) self.owner.native_owner.closeInput() else self.owner.native_owner.destroyOutput(self.index - 1) catch {};
        waits.requestStep(self.owner.admission.lease);
    }
    fn read(raw: *anyopaque) !void {
        const self = from(raw); if (self.index == 0 or self.acknowledged) return;
        try self.owner.mutate();
        if (self.index == 1) self.owner.demand.stdout = true else self.owner.demand.stderr = true;
        waits.requestStep(self.owner.admission.lease);
    }
    fn write(raw: *anyopaque, bytes: []const u8, token: u64) !void {
        const self = from(raw); if (self.index != 0) return error.BrokenPipe;
        try self.owner.mutate(); defer waits.requestStep(self.owner.admission.lease);
        try self.owner.native_owner.beginChunk(bytes, token); self.write_pending = true;
    }
    fn finish(raw: *anyopaque, token: u64) !bool {
        const self = from(raw); if (self.index != 0 or self.acknowledged) return true;
        if (self.final_token != null) return error.NativeChildSocketFinalAlreadyPending;
        try self.owner.mutate(); defer waits.requestStep(self.owner.admission.lease);
        try self.owner.native_owner.finishInput(); self.final_token = token; return false;
    }
    fn destroy(raw: *anyopaque, token: u64) !bool {
        const self = from(raw); if (self.acknowledged) return true;
        if (self.destroy_token != null) return error.NativeChildSocketDestroyAlreadyPending;
        try self.owner.mutate(); defer waits.requestStep(self.owner.admission.lease);
        if (self.index == 0) self.owner.native_owner.closeInput() else try self.owner.native_owner.destroyOutput(self.index - 1);
        self.destroy_token = token; return false;
    }
    fn reference(raw: *anyopaque, value: bool) !void {
        const self = from(raw); try self.owner.guard(); self.referenced = value;
        wake.notify(self.owner.admission.control.wake_ref);
    }
    fn errorValue(raw: *anyopaque, engine: *js.Engine, failure: anyerror) !c.JSValue {
        const self = from(raw); try self.owner.guard();
        return self.owner.errors.value(self.owner.errors.context, engine, failure);
    }
};
pub const Owner = struct {
    allocator: std.mem.Allocator, hub: *env.Hub, admission: scheduler.OwnerBridge.FailedAdmission,
    native_owner: native.Owner, errors: pipes.ErrorValues, external: Hooks,
    references: usize = 1, endpoints: [3]Endpoint,
    sockets: [3]?socket.Owned = .{null} ** 3,
    demand: @import("native_child_process_async_transport.zig").Demand = .{ .stdout = false, .stderr = false },
    frame: [6]Event = undefined, frame_count: usize = 0, frame_index: usize = 0,
    frame_resubmit: bool = false, enabled: bool = false, failed_assembly: bool = false,
    retire_requested: bool = false, retiring: bool = false, stopped: bool = false, busy: bool = false,
    fn guard(self: *Owner) !void { if (self.stopped or self.retiring) return error.NativeChildSocketOwnerDetached; try self.hub.assertOwner(); }
    fn mutate(self: *Owner) !void { try self.guard(); try waits.withdraw(self.admission.lease); }
    fn releaseReference(self: *Owner) void { self.references -= 1; if (self.references == 0) { self.errors.release(self.errors.context); self.allocator.destroy(self); } }
    /// Consumes admission on both success and error. external.release owns the
    /// separately retained provider context; no worker stores that context.
    pub fn create(engine: *js.Engine, admission: scheduler.OwnerBridge.FailedAdmission, provider: *socket.Provider, errors: pipes.ErrorValues, external: Hooks) !*Owner {
        return createWithRecords(engine, admission, provider, errors, external, null);
    }
    pub fn createWithRecords(engine: *js.Engine, admission: scheduler.OwnerBridge.FailedAdmission, provider: *socket.Provider, errors: pipes.ErrorValues, external: Hooks, records: ?*[3]?pipe_record.Owned) !*Owner {
        const self = try createBoundRecords(engine, admission, errors, external, records);
        errdefer self.abortAssembly();
        try self.createSockets(provider); return self;
    }
    /// Native failure still owns actual parent endpoints. Binding precedes the
    /// return from Process.spawn; Socket construction belongs to the prototype.
    pub fn createBoundRecords(engine: *js.Engine, admission: scheduler.OwnerBridge.FailedAdmission, errors: pipes.ErrorValues, external: Hooks, records: ?*[3]?pipe_record.Owned) !*Owner {
        var context_owned = true; errdefer if (context_owned) external.release(engine, external.context);
        var owned = admission; var admission_owned = true;
        errdefer if (admission_owned) owned.releaseUnattached(engine);
        const self = try engine.gpa.create(Owner);
        self.* = .{ .allocator = engine.gpa, .hub = owned.control.hub, .admission = owned, .native_owner = native.Owner.adopt(owned.endpoints), .errors = errors, .external = external, .endpoints = undefined };
        errors.retain(errors.context);
        for (&self.endpoints, 0..) |*endpoint, index| endpoint.* = .{ .owner = self, .index = index, .acknowledged = self.native_owner.closed[index] };
        var registered = false;
        errdefer if (!registered) {
            if (self.admission.shutdown_ticket) |ticket| { @import("native_child_process_shutdown_windows.zig").releaseUnassociated(ticket) catch {}; self.admission.shutdown_ticket = null; }
            self.native_owner.detachAfterWithdraw(); waits.detachForShutdown(self.admission.lease, null);
            for (self.admission.roots) |value| engine.freeValue(value);
            engine.gpa.free(self.admission.roots); self.admission.config.deinit();
            self.external.release(engine, self.external.context); self.releaseReference();
        };
        admission_owned = false;
        context_owned = false;
        if (self.admission.shutdown_ticket) |ticket| { try self.native_owner.attachShutdown(ticket); self.admission.shutdown_ticket = null; }
        try waits.attachEndpoints(self.admission.lease);
        try self.admission.control.hub.addResource(.{ .raw = self, .poll = poll, .referenced = referenced, .stop = stop, .stopped = released });
        registered = true;
        errdefer {
            self.failed_assembly = true; self.enabled = true; self.retire_requested = true;
            waits.withdraw(self.admission.lease) catch {};
            self.native_owner.closeInput(); self.native_owner.destroyOutput(0) catch {}; self.native_owner.destroyOutput(1) catch {};
            waits.requestStep(self.admission.lease);
        }
        for (self.admission.config.options.stdio, 0..) |mode, index| if (mode == .pipe) {
            if (records) |actual| {
                const record = actual[index] orelse return error.NativeProcessStdioRecordRequired;
                try record.state.bind(.{ .context = &self.endpoints[index], .retain = Endpoint.retain, .release = Endpoint.release, .close = Endpoint.closeRecord, .socket_hooks = Endpoint.recordHooks, .socket_created = Endpoint.socketCreated });
                self.endpoints[index].record = record; actual[index] = null;
            }
        };
        waits.requestStep(self.admission.lease);
        return self;
    }
    pub fn createSockets(self: *Owner, provider: *socket.Provider) !void {
        const engine = self.hub.engine;
        errdefer self.abortAssembly();
        if (provider.engine != engine) return error.NativeChildSocketProviderOwnerMismatch;
        for (self.admission.config.options.stdio, 0..) |mode, index| if (mode == .pipe) {
            if (self.sockets[index] != null) return error.NativeChildSocketAlreadyConstructed;
            var scope: Scope = .{ .engine = engine }; defer scope.deinit();
            const settings = try scope.object(); try scope.put(settings, "readable", c.pi_js_bool(engine.context, @intFromBool(index > 0)));
            if (self.endpoints[index].record) |record| {
                try scope.put(settings, "handle", record.handle);
                self.sockets[index] = try provider.createFromHandle(settings);
            } else self.sockets[index] = try provider.createOwned(settings, self.endpoints[index].hooks());
        };
    }
    pub fn pipe(self: *Owner, index: usize) ?c.JSValue { if (index >= 3) return null; const value = self.sockets[index] orelse return null; return c.JS_DupValue(value.engine.context, value.socket); }
    pub fn enable(self: *Owner) !void { try self.guard(); self.enabled = true; waits.requestStep(self.admission.lease); }
    pub fn requestRetire(self: *Owner) !void { try self.guard(); self.retire_requested = true; waits.requestStep(self.admission.lease); }
    pub fn abortAssembly(self: *Owner) void {
        if (self.stopped or self.retiring) return;
        self.failed_assembly = true; self.enabled = true; self.retire_requested = true;
        waits.withdraw(self.admission.lease) catch {};
        self.native_owner.closeInput(); self.native_owner.destroyOutput(0) catch {}; self.native_owner.destroyOutput(1) catch {};
        waits.requestStep(self.admission.lease);
    }
    fn referenced(raw: *anyopaque) bool {
        const self: *Owner = @ptrCast(@alignCast(raw)); if (self.stopped) return false;
        if (self.frame_index < self.frame_count or self.retire_requested or self.retiring or self.failed_assembly) return true;
        for (self.endpoints, 0..) |endpoint, index| if ((!self.native_owner.closed[index] and endpoint.referenced) or endpoint.write_pending or endpoint.final_token != null or endpoint.destroy_token != null) return true;
        return false;
    }
    fn append(self: *Owner, event: Event) void { std.debug.assert(self.frame_count < self.frame.len); self.frame[self.frame_count] = event; self.frame_count += 1; }
    fn reason(self: *Owner, failure: ?anyerror) !c.JSValue { return if (failure) |value| self.errors.value(self.errors.context, self.admission.control.hub.engine, value) else c.pi_js_null(); }
    fn outputEvent(self: *Owner, index: usize, event: native.Output) !void {
        const value = if (self.sockets[index]) |*owned| owned else return;
        switch (event) {
            .none => {}, .bytes => |data| {
                const demand = try value.push(data);
                try self.mutate(); if (index == 1) self.demand.stdout = demand else self.demand.stderr = demand;
            },
            .eof => try value.eof(),
            .failure => |failure| {
                var scope: Scope = .{ .engine = self.admission.control.hub.engine }; defer scope.deinit();
                _ = try scope.invoke(value.socket, "destroy", &.{try scope.own(try self.reason(failure))});
            },
        }
    }
    fn poll(raw: *anyopaque) !bool {
        const self: *Owner = @ptrCast(@alignCast(raw)); const control = self.admission.control;
        try control.hub.assertOwner();
        if (self.stopped or self.busy or control.delivery_busy or !self.enabled) return false;
        const engine = control.hub.engine;
        if (self.frame_index < self.frame_count) {
            self.busy = true; control.delivery_busy = true;
            defer { self.busy = false; control.delivery_busy = false; }
            engine.native_exception_diagnostics_suppressed += 1;
            defer engine.native_exception_diagnostics_suppressed -= 1;
            const event = self.frame[self.frame_index]; self.frame_index += 1;
            defer if (self.frame_index == self.frame_count) { self.frame_count = 0; self.frame_index = 0; waits.requestStep(self.admission.lease); };
            if (self.failed_assembly) {
                switch (event) { .endpoint => |value| { if (self.endpoints[@intFromEnum(value.endpoint)].record) |*record| try record.state.acknowledgeClosed(); }, else => {} }
                return true;
            }
            switch (event) {
                .stdout => |value| try self.outputEvent(1, value), .stderr => |value| try self.outputEvent(2, value),
                .write => |completion| {
                    self.endpoints[0].write_pending = false;
                    if (self.sockets[0]) |*value| { const failure = try self.reason(completion.failure); defer engine.freeValue(failure); try value.completeWrite(completion.token, completion.acceptedBytes, failure); }
                },
                .endpoint => |completion| {
                    const endpoint = &self.endpoints[@intFromEnum(completion.endpoint)];
                    endpoint.acknowledged = true; endpoint.close_failure = completion.failure;
                    endpoint.retirement_pending = completion.retirementPending;
                    if (endpoint.record) |*record| try record.state.acknowledgeClosed();
                },
            }
            return true;
        }
        // Terminal request callbacks are separate owner entries/microtask turns.
        if (!self.failed_assembly) for (&self.endpoints, 0..) |*endpoint, index| if (endpoint.acknowledged) if (self.sockets[index]) |*value| {
            if (endpoint.final_token) |token| {
                endpoint.final_token = null; self.busy = true; control.delivery_busy = true;
                defer { self.busy = false; control.delivery_busy = false; waits.requestStep(self.admission.lease); }
                engine.native_exception_diagnostics_suppressed += 1;
                defer engine.native_exception_diagnostics_suppressed -= 1;
                // Actual Node afterShutdown ignores its async status and calls
                // callback(). Preserve that policy without losing native status
                // metadata; other terminal failures retain their ordinary reason.
                const failure = if (index == 0 and self.native_owner.shutdown_result != null) c.pi_js_null() else try self.reason(endpoint.close_failure);
                defer engine.freeValue(failure);
                try value.completeFinal(token, failure); return true;
            }
            if (endpoint.destroy_token) |token| {
                endpoint.destroy_token = null; self.busy = true; control.delivery_busy = true;
                defer { self.busy = false; control.delivery_busy = false; waits.requestStep(self.admission.lease); }
                engine.native_exception_diagnostics_suppressed += 1;
                defer engine.native_exception_diagnostics_suppressed -= 1;
                try value.completeDestroy(token, c.pi_js_null()); return true;
            }
        };
        const ready = waits.takeReady(self.admission.lease) orelse return false;
        if (ready.mask.retired) {
            if (!waits.releaseRetired(self.admission.lease)) return error.NativeChildRetirementAcknowledgementRequired;
            control.hub.removeResource(self); released(self); return true;
        }
        if (ready.failure) |failure| return @as(anyerror!bool, failure);
        if (self.retiring) return false;
        try waits.withdraw(self.admission.lease);
        const result = try self.native_owner.step(self.demand);
        if (self.native_owner.takeWriteCompletion()) |completion| self.append(.{ .write = completion });
        while (self.native_owner.takeEndpointCompletion()) |completion| self.append(.{ .endpoint = completion });
        switch (result.stdout) { .none => {}, else => self.append(.{ .stdout = result.stdout }) }
        switch (result.stderr) { .none => {}, else => self.append(.{ .stderr = result.stderr }) }
        if (self.retire_requested and self.frame_count == 0 and self.native_owner.settled()) {
            self.retiring = true; try waits.retireObserved(self.admission.lease); return true;
        }
        try waits.publish(self.admission.lease, try self.native_owner.watchSnapshot());
        self.frame_resubmit = result.resubmit.stdin or result.resubmit.stdout or result.resubmit.stderr;
        if (self.frame_count != 0 or self.frame_resubmit) waits.requestStep(self.admission.lease);
        return true;
    }
    fn stop(raw: *anyopaque) void {
        const self: *Owner = @ptrCast(@alignCast(raw)); if (self.stopped) return;
        self.stopped = true; waits.withdraw(self.admission.lease) catch {};
        self.native_owner.detachAfterWithdraw(); waits.detachForShutdown(self.admission.lease, null);
    }
    fn released(raw: *anyopaque) void {
        const self: *Owner = @ptrCast(@alignCast(raw)); self.stopped = true;
        // Controller.stopped may already have run earlier in Hub resource order.
        // Hub remains alive through all stopped callbacks; do not dereference
        // the former Controller here or from a stopped Socket hook.
        const engine = self.hub.engine;
        for (&self.sockets) |*value| if (value.*) |*owned| { owned.deinit(); value.* = null; };
        for (&self.endpoints) |*endpoint| if (endpoint.record) |*record| { record.deinit(); endpoint.record = null; };
        for (self.admission.roots) |value| engine.freeValue(value);
        engine.gpa.free(self.admission.roots); self.admission.config.deinit();
        self.external.release(engine, self.external.context); self.releaseReference();
    }
};

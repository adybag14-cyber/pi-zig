//! Real pipe-to-Socket producer adapter. Child spawn/error/exit/flushStdio/close
//! namespace assembly remains explicit; this leaf does not register a public API.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const socket = @import("native_node_net_socket.zig");
const scheduler = @import("native_child_process_driver_linux.zig");
const transport = @import("native_child_process_transport.zig");
const async_io = @import("native_child_process_async_linux.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const pipe_record = @import("native_child_process_pipe_record.zig");
pub const ErrorValues = struct {
    context: *anyopaque,
    // Independent native mapping entitlement can outlive the Driver's external
    // VM-provider root. Retain/release never enter VM or contain worker pointers.
    retain: *const fn (*anyopaque) void,
    release: *const fn (*anyopaque) void,
    // Actual node/uv errno+syscall mapper, including BrokenPipe=>EPIPE.
    value: *const fn (*anyopaque, *js.Engine, anyerror) anyerror!c.JSValue,
};
const Endpoint = struct {
    owner: *Owner, index: usize,
    referenced: bool = true, live: bool = false,
    acknowledged: bool = false, retirement_pending: bool = false,
    close_failure: ?anyerror = null,
    shutdown_failure: ?anyerror = null,
    final_token: ?u64 = null, destroy_token: ?u64 = null,
    final_ready: bool = false, write_pending: bool = false,
    record: ?pipe_record.Owned = null,
    fn from(raw: *anyopaque) *Endpoint { return @ptrCast(@alignCast(raw)); }
    fn hooks(self: *Endpoint) socket.Hooks {
        return .{ .context = self, .read = read, .write = write, .finish = finish, .destroy = destroy, .referenced = reference, .error_value = errorValue, .retain = retain, .abandon = abandon, .release = release };
    }
    fn retain(raw: *anyopaque) void { from(raw).owner.references += 1; }
    fn release(raw: *anyopaque) void { from(raw).owner.releaseReference(); }
    fn closeRecord(raw: *anyopaque) !void {
        const self = from(raw); if (self.acknowledged) return;
        const driver = self.owner.driver orelse return error.NativeChildSocketOwnerDetached;
        if (self.index == 0) try driver.closeInput() else try driver.destroyOutput(self.index - 1);
    }
    fn recordHooks(raw: *anyopaque) !socket.Hooks { return from(raw).hooks(); }
    fn socketCreated(raw: *anyopaque, actual: *const socket.Owned) !void {
        const self = from(raw); const driver = self.owner.driver orelse return error.NativeChildSocketOwnerDetached;
        if (driver.control.hub.engine != actual.engine) return error.NativeChildSocketProviderOwnerMismatch;
        if (self.owner.pipes[self.index]) |*previous| previous.deinit();
        self.owner.pipes[self.index] = actual.clone();
    }
    fn abandon(raw: *anyopaque) void {
        const self = from(raw); const driver = self.owner.driver orelse return;
        if (self.index == 0) driver.closeInput() catch {} else driver.destroyOutput(self.index - 1) catch {};
        // Driver still owns physical retirement/quarantine, including an error
        // here. No child signal or JS callback from a Socket finalizer/rollback.
    }
    fn read(raw: *anyopaque) !void {
        const self = from(raw); const driver = self.owner.driver orelse return error.NativeChildSocketOwnerDetached;
        if (self.index == 0 or self.acknowledged) return;
        if (self.index == 1) self.owner.demand.stdout = true else self.owner.demand.stderr = true;
        try driver.setDemand(self.owner.demand);
    }
    fn write(raw: *anyopaque, bytes: []const u8, token: u64) !void {
        const self = from(raw); const driver = self.owner.driver orelse return error.NativeChildSocketOwnerDetached;
        // Source exposes a writable Socket state for stdout/stderr, while its
        // real uv pipe handle is READABLE only: uv__check_before_write returns
        // EPIPE for a live non-writable handle (EBADF is only the missing fd).
        if (self.index != 0) return error.BrokenPipe;
        self.write_pending = true;
        errdefer { self.write_pending = false; self.owner.updateReferences() catch {}; }
        try self.owner.updateReferences();
        try driver.beginChunk(bytes, token);
    }
    fn finish(raw: *anyopaque, token: u64) !bool {
        const self = from(raw);
        // Source handles the actual read-only uv ENOTCONN synchronously. A
        // previously consumed actual close acknowledgement is also terminal.
        if (self.index != 0 or self.acknowledged) return true;
        const driver = self.owner.driver orelse return error.NativeChildSocketOwnerDetached;
        if (driver.transport.process.input_finished or driver.transport.finish_delivered) return true;
        if (self.final_token != null) return error.NativeChildSocketFinalAlreadyPending;
        self.final_token = token;
        errdefer { self.final_token = null; self.final_ready = false; self.owner.updateReferences() catch {}; }
        try self.owner.updateReferences();
        try driver.finishInput(); return false;
    }
    fn destroy(raw: *anyopaque, token: u64) !bool {
        const self = from(raw);
        if (self.acknowledged) return true;
        const driver = self.owner.driver orelse return error.NativeChildSocketOwnerDetached;
        if (self.destroy_token != null) return error.NativeChildSocketDestroyAlreadyPending;
        self.destroy_token = token;
        errdefer { self.destroy_token = null; self.owner.updateReferences() catch {}; }
        try self.owner.updateReferences();
        if (self.index == 0) try driver.closeInput() else try driver.destroyOutput(self.index - 1);
        return false;
    }
    fn reference(raw: *anyopaque, value: bool) !void {
        const self = from(raw); const prior = self.referenced; self.referenced = value;
        errdefer self.referenced = prior;
        try self.owner.updateReferences();
    }
    fn errorValue(raw: *anyopaque, engine: *js.Engine, failure: anyerror) !c.JSValue {
        const owner = from(raw).owner;
        if (owner.driver == null) return error.NativeChildSocketOwnerDetached;
        const mapper = owner.errors; return mapper.value(mapper.context, engine, failure);
    }
};
pub const Owner = struct {
    allocator: std.mem.Allocator,
    driver: ?*scheduler.Driver = null,
    references: usize = 1,
    external: scheduler.Hooks,
    errors: ErrorValues,
    endpoints: [3]Endpoint,
    pipes: [3]?socket.Owned = .{ null, null, null },
    process_referenced: bool = true, process_live: bool = true,
    demand: async_io.Demand = .{ .stdout = false, .stderr = false },
    failed_assembly: bool = false,
    records_bound: bool = false,

    /// Caller owns one reference until successful Driver.start takes hooks().
    /// On failed create call releaseUnstarted; actual Config ownership is Driver's.
    pub fn create(allocator: std.mem.Allocator, external: scheduler.Hooks, errors: ErrorValues) !*Owner {
        const self = try allocator.create(Owner);
        self.* = .{ .allocator = allocator, .external = external, .errors = errors, .endpoints = undefined };
        errors.retain(errors.context);
        for (&self.endpoints, 0..) |*endpoint, index| endpoint.* = .{ .owner = self, .index = index };
        return self;
    }
    fn releaseReference(self: *Owner) void {
        self.references -= 1;
        if (self.references == 0) { self.errors.release(self.errors.context); self.allocator.destroy(self); }
    }
    pub fn hooks(self: *Owner) scheduler.Hooks { return .{ .context = self, .deliver = deliver, .poll = poll, .stop = stop, .release = released }; }
    pub fn releaseUnstarted(self: *Owner, engine: *js.Engine) void {
        std.debug.assert(self.driver == null and self.references == 1);
        self.external.release(engine, self.external.context); self.releaseReference();
    }
    /// Driver/root entitlement remains alive on failure. Rollback retires actual
    /// endpoints and the exact owned child; it never frees the live Driver early.
    pub fn attach(self: *Owner, driver: *scheduler.Driver, provider: *socket.Provider, stdio: [3]transport.Stdio) !void {
        return self.attachRecords(driver, provider, stdio, null);
    }
    pub fn attachRecords(self: *Owner, driver: *scheduler.Driver, provider: *socket.Provider, stdio: [3]transport.Stdio, records: ?*[3]?pipe_record.Owned) !void {
        try self.bindRecords(driver, stdio, records);
        try self.createSockets(provider, stdio);
    }
    pub fn adoptDriver(self: *Owner, driver: *scheduler.Driver) !void {
        if (driver.hooks.context != self or (self.driver != null and self.driver != driver)) return error.NativeChildSocketDriverOwnerMismatch;
        self.driver = driver; self.process_live = driver.transport.process.exited == null;
    }
    pub fn enable(self: *Owner) !void {
        const driver = self.driver orelse return error.NativeChildSocketOwnerDetached;
        try driver.setDemand(self.demand);
    }
    pub fn requestRetire(self: *Owner) !void { const driver = self.driver orelse return error.NativeChildSocketOwnerDetached; try driver.requestRetire(); }
    fn rollbackAssembly(self: *Owner) void {
        self.failed_assembly = true;
        const driver = self.driver orelse return;
        driver.closeInput() catch {};
        driver.destroyOutput(0) catch {}; driver.destroyOutput(1) catch {};
        _ = driver.signalNumber(9) catch false;
        driver.requestRetire() catch {};
    }
    pub fn abortAssembly(self: *Owner) void { self.rollbackAssembly(); }
    /// Native Process.spawn phase: bind actual endpoints without entering any
    /// guest Socket constructor or _read hook before the native call returns.
    pub fn bindRecords(self: *Owner, driver: *scheduler.Driver, stdio: [3]transport.Stdio, records: ?*[3]?pipe_record.Owned) !void {
        if (self.records_bound) return error.NativeChildSocketDriverOwnerMismatch;
        try self.adoptDriver(driver); self.records_bound = true;
        errdefer self.rollbackAssembly();
        try driver.setDemand(self.demand);
        for (stdio, 0..) |mode, index| if (mode == .pipe) {
            self.endpoints[index].live = true;
            if (records) |actual| {
                const record = actual[index] orelse return error.NativeProcessStdioRecordRequired;
                try record.state.bind(.{ .context = &self.endpoints[index], .retain = Endpoint.retain, .release = Endpoint.release, .close = Endpoint.closeRecord, .socket_hooks = Endpoint.recordHooks, .socket_created = Endpoint.socketCreated });
                self.endpoints[index].record = record; actual[index] = null;
            }
        };
        try self.updateReferences();
    }
    /// Source prototype phase, after live _handle.spawn has returned.
    pub fn createSockets(self: *Owner, provider: *socket.Provider, stdio: [3]transport.Stdio) !void {
        const driver = self.driver orelse return error.NativeChildSocketOwnerDetached;
        errdefer self.rollbackAssembly();
        const engine = driver.control.hub.engine;
        if (provider.engine != engine) return error.NativeChildSocketProviderOwnerMismatch;
        for (stdio, 0..) |mode, index| if (mode == .pipe) {
            if (self.pipes[index] != null) return error.NativeChildSocketAlreadyConstructed;
            var scope: Scope = .{ .engine = engine }; defer scope.deinit();
            const settings = try scope.object(); try scope.put(settings, "readable", c.pi_js_bool(engine.context, @intFromBool(index > 0)));
            if (self.endpoints[index].record) |record| {
                try scope.put(settings, "handle", record.handle);
                self.pipes[index] = try provider.createFromHandle(settings);
            } else self.pipes[index] = try provider.createOwned(settings, self.endpoints[index].hooks());
        };
    }
    pub fn pipe(self: *Owner, index: usize) ?c.JSValue {
        if (index >= 3) return null; const value = self.pipes[index] orelse return null;
        return c.JS_DupValue(value.engine.context, value.socket);
    }
    pub fn referenceProcess(self: *Owner, value: bool) !void {
        const prior = self.process_referenced; self.process_referenced = value;
        errdefer self.process_referenced = prior;
        try self.updateReferences();
    }
    fn updateReferences(self: *Owner) !void {
        const driver = self.driver orelse return;
        var referenced = self.process_live and self.process_referenced;
        for (self.endpoints) |endpoint| referenced = referenced or (endpoint.live and endpoint.referenced) or endpoint.write_pending or endpoint.final_token != null or endpoint.destroy_token != null;
        try driver.setReferenced(referenced);
    }
    fn reason(self: *Owner, engine: *js.Engine, failure: ?anyerror) !c.JSValue {
        try engine.checkNativeEntry();
        const value = failure orelse return c.pi_js_null();
        if (value == error.OutOfMemory) return error.OutOfMemory;
        if (value == error.JavaScriptException) {
            const captured = engine.captured_exception orelse return error.NativeChildSocketMissingException;
            return c.JS_DupValue(engine.context, captured);
        }
        var scope: @import("native_node_socket_scope.zig").Scope = .{ .engine = engine };
        defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
        const mapped = try scope.own(try self.errors.value(self.errors.context, engine, value));
        return c.JS_DupValue(engine.context, mapped);
    }
    fn deliver(engine: *js.Engine, raw: *anyopaque, driver: *scheduler.Driver, event: scheduler.Event) !void {
        const self: *Owner = @ptrCast(@alignCast(raw));
        if (self.failed_assembly) {
            // No Socket data callback after a failed factory, but genuine native
            // record close callbacks still follow observed endpoint retirement.
            switch (event) { .endpoint => |value| { if (self.endpoints[@intFromEnum(value.endpoint)].record) |*record| try record.state.acknowledgeClosed(); }, else => {} }
            return;
        }
        switch (event) {
            .stdout => |output_value| try self.output(engine, 1, output_value),
            .stderr => |output_value| try self.output(engine, 2, output_value),
            .write => |completion| if (self.pipes[0]) |*value| {
                self.endpoints[0].write_pending = false;
                errdefer self.updateReferences() catch {};
                const failure = try self.reason(engine, completion.failure); defer engine.freeValue(failure);
                try value.completeWrite(completion.token, completion.acceptedBytes, failure);
                try self.updateReferences();
            },
            .endpoint => |completion| {
                const index: usize = @intFromEnum(completion.endpoint); const endpoint = &self.endpoints[index];
                endpoint.acknowledged = true; endpoint.retirement_pending = completion.retirementPending;
                endpoint.close_failure = completion.failure; endpoint.live = false;
                if (endpoint.record) |*record| try record.state.acknowledgeClosed();
                try self.updateReferences();
                // Queue already observed state through the bounded owner hook,
                // after this callback's microtask boundary, never inline in _final.
                if (endpoint.final_token != null) endpoint.final_ready = true;
                @import("native_child_process_epoll_linux.zig").requestStep(driver.lease);
            },
            .input_finished => |completion| {
                // Actual request completion preserves native failure metadata;
                // Source afterShutdown itself ignores status and invokes cb().
                self.endpoints[0].shutdown_failure = completion.failure;
                if (self.endpoints[0].final_token != null) self.endpoints[0].final_ready = true;
                @import("native_child_process_epoll_linux.zig").requestStep(driver.lease);
            },
            .exit => {
                self.process_live = false; try self.updateReferences();
                try self.external.deliver(engine, self.external.context, driver, event);
            },
            else => try self.external.deliver(engine, self.external.context, driver, event),
        }
    }
    fn output(self: *Owner, engine: *js.Engine, index: usize, value: async_io.Output) !void {
        const pipe_value = if (self.pipes[index]) |*owned| owned else return;
        switch (value) {
            .none => {}, .bytes => |data| {
                const demand = try pipe_value.push(data); // Copy before guest push.
                if (index == 1) self.demand.stdout = demand else self.demand.stderr = demand;
                if (self.driver) |driver| try driver.setDemand(self.demand);
            },
            .eof => try pipe_value.eof(),
            .failure => |failure| {
                var scope: Scope = .{ .engine = engine }; defer scope.deinit();
                const error_value = try scope.own(try self.reason(engine, failure));
                _ = try scope.invoke(pipe_value.socket, "destroy", &.{error_value});
            },
        }
    }
    fn poll(engine: *js.Engine, raw: *anyopaque, driver: *scheduler.Driver) !bool {
        const self: *Owner = @ptrCast(@alignCast(raw));
        if (self.failed_assembly) return false;
        for (&self.endpoints, 0..) |*endpoint, index| if (self.pipes[index]) |*value| {
            if (endpoint.final_ready) if (endpoint.final_token) |token| {
                endpoint.final_ready = false; endpoint.final_token = null;
                errdefer self.updateReferences() catch {};
                // net.afterShutdown completes cb() after asynchronous shutdown;
                // it does not pass the kernel request's status as a new error.
                // Immediate admission/shutdown failures still throw at finish.
                const failure = if (index == 0) c.pi_js_null() else try self.reason(engine, endpoint.close_failure);
                defer engine.freeValue(failure);
                try value.completeFinal(token, failure); try self.updateReferences(); return true;
            };
            if (endpoint.acknowledged) if (endpoint.destroy_token) |token| {
                endpoint.destroy_token = null;
                errdefer self.updateReferences() catch {};
                // Retirement diagnostics stay in endpoint metadata. Socket close
                // carries its original _destroy exception boolean, not a new one.
                try value.completeDestroy(token, c.pi_js_null()); try self.updateReferences(); return true;
            };
        };
        return if (self.external.poll) |owner_poll| owner_poll(engine, self.external.context, driver) else false;
    }
    fn stop(raw: *anyopaque) void { const self: *Owner = @ptrCast(@alignCast(raw)); self.driver = null; self.external.stop(self.external.context); }
    fn released(engine: *js.Engine, raw: *anyopaque) void {
        const self: *Owner = @ptrCast(@alignCast(raw)); self.driver = null;
        for (&self.pipes) |*value| if (value.*) |*owned| { owned.deinit(); value.* = null; };
        for (&self.endpoints) |*endpoint| if (endpoint.record) |*record| { record.deinit(); endpoint.record = null; };
        self.external.release(engine, self.external.context); self.releaseReference();
    }
};

//! Native Env I/O workers own only native data. Promise and callback settlement runs on the VM owner.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
pub const Task = struct {
    hub: *Hub,
    work: *const fn (*Task) void,
    complete: *const fn (*Task) anyerror!void,
    destroy: *const fn (*Task) void,
    cancel: *const fn (*Task) void,
    poll: ?*const fn (*Task) anyerror!bool = null,
    resolve: c.JSValue,
    reject: c.JSValue,
    done: std.atomic.Value(bool) = .init(false),
    abandoned: bool = false,
    // Callback APIs retire the completed task before propagating a guest throw.
    // Promise tasks preserve their existing rejection behavior by default.
    propagate_completion_errors: bool = false,
    pub fn finish(self: *Task) void {
        const engine = self.hub.engine;
        self.done.store(true, .release);
        js.Engine.notifyOwner(engine);
    }
    pub fn settled(self: *Task, failed: bool, value: c.JSValue) !void {
        const engine = self.hub.engine;
        const function = if (failed) self.reject else self.resolve;
        const ignored = try js.call(engine, function, c.pi_js_undefined(), &.{value});
        engine.freeValue(ignored);
    }
    pub fn releaseFunctions(self: *Task) void {
        self.hub.engine.freeValue(self.resolve);
        self.hub.engine.freeValue(self.reject);
    }
};
pub const Resource = struct {
    raw: *anyopaque,
    stop: *const fn (*anyopaque) void,
    stopped: *const fn (*anyopaque) void,
    tag: ?*const anyopaque = null,
    poll: ?*const fn (*anyopaque) anyerror!bool = null,
    referenced: ?*const fn (*anyopaque) bool = null,
    bind_host_wake: ?*const fn (*anyopaque, *const fn (?*anyopaque) void, ?*anyopaque) void = null,
    detach_host_wake: ?*const fn (*anyopaque) void = null,
};
pub const Hub = struct {
    engine: *js.Engine,
    io: std.Io,
    owner: std.Thread.Id,
    group: std.Io.Group = .init,
    tasks: std.ArrayList(*Task) = .empty,
    resources: std.ArrayList(Resource) = .empty,
    stopping: bool = false,
    pumping: bool = false,
    pub fn assertOwner(self: *Hub) !void {
        if (std.Thread.getCurrentId() != self.owner) return error.NativeEnvOwnerThreadRequired;
    }
    pub fn submit(self: *Hub, task: *Task) !void {
        try self.assertOwner();
        if (self.stopping) return error.NativeEnvClosed;
        try self.tasks.append(self.engine.gpa, task);
        errdefer _ = self.tasks.pop();
        try self.group.concurrent(self.io, runTask, .{task});
    }
    fn runTask(task: *Task) void {
        task.work(task);
    }
    pub fn addResource(self: *Hub, resource: Resource) !void {
        try self.assertOwner();
        try self.resources.append(self.engine.gpa, resource);
    }
    pub fn removeResource(self: *Hub, raw: *anyopaque) void {
        for (self.resources.items, 0..) |resource, index| if (resource.raw == raw) {
            _ = self.resources.orderedRemove(index);
            return;
        };
    }
    fn pump(engine: *js.Engine) anyerror!bool {
        const self: *Hub = @ptrCast(@alignCast(engine.native_env_context orelse return false));
        try self.assertOwner();
        if (self.pumping or self.stopping) return false;
        self.pumping = true;
        defer self.pumping = false;
        // Native I/O callbacks enter at a microtask checkpoint. A completed
        // worker must not overtake queued Promise continuations from the
        // current callback, even if its OS operation already finished.
        if (c.JS_IsJobPending(engine.runtime)) return false;
        var worked = false;
        var index: usize = 0;
        while (index < self.tasks.items.len) {
            const task = self.tasks.items[index];
            if (task.poll) |poll| {
                worked = (try poll(task)) or worked;
                if (c.JS_IsJobPending(engine.runtime)) return worked;
            }
            if (!task.done.load(.acquire)) {
                index += 1;
                continue;
            }
            _ = self.tasks.orderedRemove(index);
            defer task.destroy(task);
            if (!task.abandoned) task.complete(task) catch |err| {
                if (task.propagate_completion_errors) return err;
                _ = @import("native_durable.zig").reject(engine, err);
                const reason = c.JS_GetException(engine.context);
                defer engine.freeValue(reason);
                try task.settled(true, reason);
            };
            worked = true;
            if (c.JS_IsJobPending(engine.runtime)) return worked;
        }
        var resource_index: usize = 0;
        while (resource_index < self.resources.items.len) {
            const resource = self.resources.items[resource_index];
            if (resource.poll) |poll| {
                worked = (try self.pollResource(resource, poll)) or worked;
                if (c.JS_IsJobPending(engine.runtime)) return worked;
            }
            // Other native resources may retire during a callback. A scheduler
            // controller itself stays registered until teardown.
            if (resource_index < self.resources.items.len and self.resources.items[resource_index].raw == resource.raw) resource_index += 1;
        }
        return worked;
    }
    fn pollResource(self: *Hub, resource: Resource, callback: *const fn (*anyopaque) anyerror!bool) !bool {
        const engine = self.engine;
        engine.native_exception_diagnostics_suppressed += 1;
        defer engine.native_exception_diagnostics_suppressed -= 1;
        // The actual owner-thread VM delivery boundary, including direct
        // native stream producer callbacks and their synchronous cleanup.
        try engine.checkNativeEntry();
        var invocation: js.Engine.NativeInvocation = .{};
        engine.enterNativeInvocation(&invocation);
        const worked = callback(resource.raw) catch |err| {
            if (err == error.OutOfMemory) _ = engine.throwNativeOutOfMemoryFatal()
            else if (err == error.JavaScriptException) _ = engine.throwCaptured();
            _ = try engine.checked(engine.leaveNativeInvocation(&invocation, c.pi_js_undefined()));
            return err;
        };
        _ = try engine.checked(engine.leaveNativeInvocation(&invocation, c.pi_js_undefined()));
        return worked;
    }
    fn deinit(engine: *js.Engine) void {
        const self: *Hub = @ptrCast(@alignCast(engine.native_env_context orelse return));
        self.stopping = true;
        // Stop every exact native lease before joining workers; workers never enter the VM during shutdown.
        for (self.resources.items) |resource| resource.stop(resource.raw);
        for (self.tasks.items) |task| {
            task.abandoned = true;
            task.cancel(task);
        }
        self.group.cancel(self.io);
        // Retire task tickets before their transports. Live resources keep a process lease until stopped().
        for (self.tasks.items) |task| task.destroy(task);
        for (self.resources.items) |resource| resource.stopped(resource.raw);
        self.tasks.deinit(engine.gpa);
        self.resources.deinit(engine.gpa);
        engine.native_env_context = null;
        engine.native_env_pump = null;
        engine.native_env_deinit = null;
        engine.gpa.destroy(self);
    }
};
pub fn hasReferenced(engine: *js.Engine) bool {
    const raw = engine.native_env_context orelse return false;
    const self: *Hub = @ptrCast(@alignCast(raw));
    if (self.stopping) return false;
    for (self.tasks.items) |task| if (!task.abandoned) return true;
    for (self.resources.items) |resource| if (resource.referenced) |referenced| if (referenced(resource.raw)) return true;
    return false;
}
/// Old Task.poll producers have not all published incremental readiness yet.
/// Keep their existing idle fallback; ported Resource producers use real wake.
pub fn needsLegacyPolling(engine: *js.Engine) bool {
    const raw = engine.native_env_context orelse return false;
    const self: *Hub = @ptrCast(@alignCast(raw));
    for (self.tasks.items) |task| if (!task.abandoned and task.poll != null) return true;
    return false;
}
/// Called on the VM owner immediately after its real host notifier is installed.
/// Existing native resources may have been created during module activation.
pub fn bindHostNotifiers(engine: *js.Engine) void {
    const publish = engine.host_owner_notify orelse return;
    const raw = engine.native_env_context orelse return;
    const self: *Hub = @ptrCast(@alignCast(raw));
    std.debug.assert(std.Thread.getCurrentId() == self.owner);
    if (self.stopping) return;
    for (self.resources.items) |resource| if (resource.bind_host_wake) |bind| bind(resource.raw, publish, engine.host_owner_notify_context);
}
pub fn detachHostNotifiers(engine: *js.Engine) void {
    const raw = engine.native_env_context orelse return;
    const self: *Hub = @ptrCast(@alignCast(raw));
    for (self.resources.items) |resource| if (resource.detach_host_wake) |detach| detach(resource.raw);
}
pub fn get(engine: *js.Engine) !*Hub {
    if (engine.native_env_context) |raw| return @ptrCast(@alignCast(raw));
    const io = engine.native_io orelse return error.NativeIoRequired;
    const self = try engine.gpa.create(Hub);
    self.* = .{ .engine = engine, .io = io, .owner = std.Thread.getCurrentId() };
    engine.native_env_context = self;
    engine.native_env_pump = Hub.pump;
    engine.native_env_deinit = Hub.deinit;
    return self;
}

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
};
pub const Hub = struct {
    engine: *js.Engine,
    io: std.Io,
    owner: std.Thread.Id,
    group: std.Io.Group = .init,
    tasks: std.ArrayList(*Task) = .empty,
    resources: std.ArrayList(Resource) = .empty,
    stopping: bool = false,
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
        var worked = false;
        var index: usize = 0;
        while (index < self.tasks.items.len) {
            const task = self.tasks.items[index];
            if (task.poll) |poll| worked = (try poll(task)) or worked;
            if (!task.done.load(.acquire)) {
                index += 1;
                continue;
            }
            _ = self.tasks.orderedRemove(index);
            defer task.destroy(task);
            if (!task.abandoned) task.complete(task) catch |err| {
                _ = @import("native_durable.zig").reject(engine, err);
                const reason = c.JS_GetException(engine.context);
                defer engine.freeValue(reason);
                try task.settled(true, reason);
            };
            worked = true;
        }
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

//! A retained native worker receives catalog snapshots without holding its
//! ordinary invocation mutex. Sources only signal wakeups from native locks.
const std = @import("std");
const json = @import("../durable/backend/json.zig");
const runtime = @import("js_runtime.zig");
pub const Features = struct { codemode: bool = true, tool_search: bool = true, mcp: bool = true };
pub const Source = struct {
    context: ?*anyopaque,
    build: *const fn (?*anyopaque, std.mem.Allocator, Features) anyerror!json.Owned,
    subscribe: *const fn (?*anyopaque, *std.Io.Event) anyerror!void,
    unsubscribe: *const fn (?*anyopaque, *std.Io.Event) void,
    registration_allowed: ?*const fn (?*anyopaque, []const u8) bool = null,
    native_tool_activatable: ?*const fn (?*anyopaque, []const u8) bool = null,
};
pub const Publisher = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    view: *runtime.Runtime,
    source: Source,
    features: Features,
    wake: std.Io.Event = .unset,
    jobs: std.Io.Group = .init,
    stopping: std.atomic.Value(bool) = .init(false),
    status_mutex: std.Io.Mutex = .init,
    last_failure: ?anyerror = null,
    publication: std.atomic.Value(u64) = .init(0),
    pub fn create(gpa: std.mem.Allocator, owner: *runtime.Runtime, source: Source, features: Features) !*Publisher {
        const self = try gpa.create(Publisher);
        errdefer gpa.destroy(self);
        const view = try owner.extensionView(1, "<native-catalog-publisher>");
        errdefer view.deinit();
        self.* = .{ .gpa = gpa, .io = owner.io, .view = view, .source = source, .features = features };
        try source.subscribe(source.context, &self.wake);
        errdefer source.unsubscribe(source.context, &self.wake);
        try self.publish();
        try self.jobs.concurrent(self.io, run, .{self});
        return self;
    }
    fn publish(self: *Publisher) !void {
        var snapshot = try self.source.build(self.source.context, std.heap.page_allocator, self.features);
        defer snapshot.deinit();
        try self.view.admitNativeToolCatalog(snapshot.value);
        _ = self.publication.fetchAdd(1, .release);
    }
    fn run(self: *Publisher) void {
        while (!self.stopping.load(.acquire)) {
            self.wake.wait(self.io) catch return;
            self.wake.reset();
            if (self.stopping.load(.acquire)) return;
            var publish_failure: ?anyerror = null;
            self.publish() catch |err| {
                publish_failure = err;
            };
            self.status_mutex.lockUncancelable(self.io);
            self.last_failure = publish_failure;
            self.status_mutex.unlock(self.io);
        }
    }
    pub fn failure(self: *Publisher) ?anyerror {
        self.status_mutex.lockUncancelable(self.io);
        defer self.status_mutex.unlock(self.io);
        return self.last_failure;
    }
    pub fn deinit(self: *Publisher) void {
        self.source.unsubscribe(self.source.context, &self.wake);
        self.stopping.store(true, .release);
        self.wake.set(self.io);
        self.jobs.cancel(self.io);
        self.jobs.await(self.io) catch {};
        self.view.deinit();
        self.gpa.destroy(self);
    }
};

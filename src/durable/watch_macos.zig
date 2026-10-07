//! Owned aggregate FSEvents stream; snapshots and lexical scope stay in watch.zig.
const std = @import("std");
const builtin = @import("builtin");
const CFRef = *const anyopaque;
const Stream = *anyopaque;
const ArrayCallbacks = extern struct { version: isize, retain: ?*const anyopaque, release: ?*const anyopaque, description: ?*const anyopaque, equal: ?*const anyopaque };
const StreamContext = extern struct { version: isize = 0, info: ?*anyopaque, retain: ?*const anyopaque = null, release: ?*const anyopaque = null, description: ?*const anyopaque = null };
extern "CoreFoundation" var kCFTypeArrayCallBacks: ArrayCallbacks;
extern "CoreFoundation" var kCFRunLoopDefaultMode: CFRef;
extern "CoreFoundation" fn CFRetain(CFRef) CFRef;
extern "CoreFoundation" fn CFRelease(CFRef) void;
extern "CoreFoundation" fn CFStringCreateWithBytes(?CFRef, [*]const u8, isize, u32, u8) ?CFRef;
extern "CoreFoundation" fn CFArrayCreate(?CFRef, [*]const CFRef, isize, *const ArrayCallbacks) ?CFRef;
extern "CoreFoundation" fn CFRunLoopGetCurrent() CFRef;
extern "CoreFoundation" fn CFRunLoopRunInMode(CFRef, f64, u8) i32;
const EventCallback = *const fn (Stream, ?*anyopaque, usize, *anyopaque, [*]const u32, [*]const u64) callconv(.c) void;
extern "CoreServices" fn FSEventStreamCreate(?CFRef, EventCallback, *StreamContext, CFRef, u64, f64, u32) ?Stream;
extern "CoreServices" fn FSEventStreamScheduleWithRunLoop(Stream, CFRef, CFRef) void;
extern "CoreServices" fn FSEventStreamStart(Stream) u8;
extern "CoreServices" fn FSEventStreamStop(Stream) void;
extern "CoreServices" fn FSEventStreamInvalidate(Stream) void;
extern "CoreServices" fn FSEventStreamRelease(Stream) void;
pub const Installed = struct { inode: std.Io.File.INode, device: u64, canonical: []u8, string: CFRef, directory: bool };
const Context = struct {
    gpa: std.mem.Allocator,
    owner: ?*Backend = null,
    paths: std.ArrayList([]u8) = .empty,
    rescan: bool = false,
    failure: ?anyerror = null,
    fn clear(self: *Context) void {
        for (self.paths.items) |path| self.gpa.free(path);
        self.paths.clearRetainingCapacity();
    }
    fn callback(_: Stream, raw: ?*anyopaque, count: usize, raw_paths: *anyopaque, flags: [*]const u32, _: [*]const u64) callconv(.c) void {
        const self: *Context = @ptrCast(@alignCast(raw.?));
        if (self.failure != null) return;
        const paths: [*]const [*:0]const u8 = @ptrCast(@alignCast(raw_paths));
        for (0..count) |index| {
            if (flags[index] & 7 != 0) self.rescan = true;
            if (flags[index] & 0x10 != 0) continue; // Historical sentinel, not a path change.
            self.owner.?.record(std.mem.span(paths[index])) catch |err| {
                self.failure = err;
                return;
            };
        }
    }
};
fn within(path: []const u8, parent: []const u8) bool {
    if (std.mem.eql(u8, path, parent)) return true;
    if (!std.mem.startsWith(u8, path, parent)) return false;
    return parent.len != 0 and (parent[parent.len - 1] == '/' or (path.len > parent.len and path[parent.len] == '/'));
}
pub const Backend = struct {
    gpa: std.mem.Allocator,
    installed: std.StringHashMapUnmanaged(Installed) = .empty,
    context: *Context,
    stream: ?Stream = null,
    array: ?CFRef = null,
    runloop: ?CFRef = null,
    runloop_thread: ?std.Thread.Id = null,
    started: bool = false,
    dirty: bool = true,
    pub fn init(gpa: std.mem.Allocator) !Backend {
        if (builtin.os.tag != .macos) return error.OperationUnsupported;
        const context = try gpa.create(Context);
        context.* = .{ .gpa = gpa };
        return .{ .gpa = gpa, .context = context };
    }
    fn stop(self: *Backend) void {
        if (self.stream) |stream| {
            if (self.started) FSEventStreamStop(stream);
            FSEventStreamInvalidate(stream);
            FSEventStreamRelease(stream);
        }
        self.stream = null;
        self.started = false;
        if (self.array) |array| CFRelease(array);
        self.array = null;
    }
    /// Retire scheduled streams on their run-loop owner before joining it.
    /// Source notify 8.2 performs Stop/Invalidate/Release on that worker.
    pub fn retireOnOwnerThread(self: *Backend) void {
        if (self.runloop_thread) |owner| std.debug.assert(owner == std.Thread.getCurrentId());
        self.stop();
        if (self.runloop) |runloop| CFRelease(runloop);
        self.runloop = null;
        self.runloop_thread = null;
    }
    pub fn deinit(self: *Backend) void {
        // Constructor rollback may own an unscheduled stream. Once scheduled,
        // the worker must retire it before the caller frees callback metadata.
        std.debug.assert(self.runloop == null and self.runloop_thread == null);
        self.stop();
        var iterator = self.installed.iterator();
        while (iterator.next()) |entry| {
            CFRelease(entry.value_ptr.string);
            self.gpa.free(entry.value_ptr.canonical);
            self.gpa.free(entry.key_ptr.*);
        }
        self.installed.deinit(self.gpa);
        self.context.clear();
        self.context.paths.deinit(self.gpa);
        self.gpa.destroy(self.context);
    }
    pub fn remove(self: *Backend, path: []const u8) void {
        const entry = self.installed.fetchRemove(path) orelse return;
        CFRelease(entry.value.string);
        self.gpa.free(entry.value.canonical);
        self.gpa.free(entry.key);
        self.dirty = true;
    }
    pub fn add(self: *Backend, path: []const u8, inode: std.Io.File.INode, device: u64) !bool {
        if (self.installed.contains(path)) return false;
        const terminated = try self.gpa.dupeZ(u8, path);
        defer self.gpa.free(terminated);
        var canonical_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const canonical_c = std.c.realpath(terminated, &canonical_buffer) orelse return false;
        var metadata: std.c.Stat = undefined;
        if (std.c.fstatat(std.c.AT.FDCWD, terminated, &metadata, 0) != 0) return false;
        const canonical = try self.gpa.dupe(u8, std.mem.span(canonical_c));
        errdefer self.gpa.free(canonical);
        const owned = try self.gpa.dupe(u8, path);
        errdefer self.gpa.free(owned);
        const string = CFStringCreateWithBytes(null, path.ptr, @intCast(path.len), 0x08000100, 0) orelse return error.NativeWatchUnavailable;
        errdefer CFRelease(string);
        try self.installed.put(self.gpa, owned, .{ .inode = inode, .device = device, .canonical = canonical, .string = string, .directory = metadata.mode & 0o170000 == 0o040000 });
        self.dirty = true;
        return true;
    }
    /// Prepare all fallible native stream metadata before publishing open.
    /// Scheduling and delivery are owned by the subsequent watcher thread.
    pub fn prepare(self: *Backend) !void {
        if (!self.dirty) return;
        self.stop();
        self.context.owner = self;
        if (self.installed.count() == 0) {
            self.dirty = false;
            return;
        }
        const strings = try self.gpa.alloc(CFRef, self.installed.count());
        defer self.gpa.free(strings);
        var iterator = self.installed.valueIterator();
        var index: usize = 0;
        while (iterator.next()) |installed| : (index += 1) strings[index] = installed.string;
        const array = CFArrayCreate(null, strings.ptr, @intCast(strings.len), &kCFTypeArrayCallBacks) orelse return error.NativeWatchUnavailable;
        self.array = array;
        var context: StreamContext = .{ .info = self.context };
        // Source notify 8.2 uses FileEvents|NoDefer, zero latency and SinceNow.
        self.stream = FSEventStreamCreate(null, Context.callback, &context, array, std.math.maxInt(u64), 0.0, 0x12) orelse return error.NativeWatchUnavailable;
        self.dirty = false;
    }
    fn record(self: *Backend, path: []const u8) !void {
        var iterator = self.installed.iterator();
        while (iterator.next()) |entry| {
            const installed = entry.value_ptr.*;
            if (!within(path, installed.canonical)) continue;
            var relative = path[installed.canonical.len..];
            while (relative.len > 0 and relative[0] == '/') relative = relative[1..];
            if (!installed.directory and relative.len != 0) continue;
            if (installed.directory and std.mem.indexOfScalar(u8, relative, '/') != null) continue;
            const owned = if (relative.len == 0) try self.gpa.dupe(u8, entry.key_ptr.*) else try std.fs.path.join(self.gpa, &.{ entry.key_ptr.*, relative });
            errdefer self.gpa.free(owned);
            try self.context.paths.append(self.gpa, owned);
        }
    }
    pub fn drain(self: *Backend, sink: anytype) !void {
        try self.prepare();
        if (self.stream) |stream| {
            if (!self.started) {
                if (self.runloop == null) {
                    self.runloop = CFRetain(CFRunLoopGetCurrent());
                    self.runloop_thread = std.Thread.getCurrentId();
                }
                FSEventStreamScheduleWithRunLoop(stream, self.runloop.?, kCFRunLoopDefaultMode);
                if (FSEventStreamStart(stream) == 0) return error.NativeWatchUnavailable;
                self.started = true;
            }
            _ = CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.001, 1);
        }
        if (self.context.failure) |err| return err;
        if (self.context.rescan) {
            self.context.rescan = false;
            try sink.overflow();
        }
        defer self.context.clear();
        for (self.context.paths.items) |path| try sink.event(path);
    }
};
pub fn unreliable(_: std.mem.Allocator, _: anytype) !bool {
    return false;
}

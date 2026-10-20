//! Shared native-only fixture for the actual Debug and Permission leaves.
//! Placement storage has a separate charged native entitlement. No Engine,
//! process.env interceptor, public permission namespace or fake policy is used.
const std = @import("std");
pub const c = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("engine_abi.h");
    @cInclude("native_node_native_debug.h");
    @cInclude("native_node_permission_test_support.h");
    @cInclude("native_node_environment_map_test_support.h");
    @cInclude("native_node_options_environment.h");
    @cInclude("uv.h");
    @cInclude("fcntl.h");
});
pub const memory_limit: usize = 32 * 1024 * 1024;
pub const Span = c.PiNodeEnvironmentPathSpan;
pub const Storage = struct {
    memory: ?*anyopaque = null,
    pointer: ?[*]u8 = null,
    bytes: usize = 0,
    alignment: std.mem.Alignment = .@"1",
    charged: bool = false,
    pub fn init(self: *Storage, memory: ?*anyopaque, bytes: usize, alignment: usize) !void {
        self.* = .{ .memory = memory, .bytes = bytes, .alignment = .fromByteUnits(alignment) };
        c.pi_js_retain_memory_owner(memory);
        errdefer self.deinit();
        if (c.pi_js_native_memory_reserve(memory, bytes) == 0) return error.OutOfMemory;
        self.charged = true;
        self.pointer = std.heap.c_allocator.rawAlloc(bytes, self.alignment,
            @returnAddress()) orelse return error.OutOfMemory;
    }
    pub fn deinit(self: *Storage) void {
        if (self.pointer) |pointer| {
            self.pointer = null;
            std.heap.c_allocator.rawFree(pointer[0..self.bytes], self.alignment, @returnAddress());
        }
        if (self.charged) {
            self.charged = false;
            c.pi_js_native_memory_release(self.memory, self.bytes);
        }
        if (self.memory) |memory| {
            self.memory = null;
            c.pi_js_release_memory_owner(memory);
        }
    }
};
pub const Fixture = struct {
    runtime: ?*c.JSRuntime = null,
    context: ?*c.JSContext = null,
    memory: ?*anyopaque = null,
    paths_storage: Storage = .{},
    debug_storage: Storage = .{},
    permission_storage: Storage = .{},
    paths: ?*c.PiNodeEnvironmentPaths = null,
    map: ?*c.PiNodeEnvironmentMap = null,
    debug_list: ?*c.PiNodeNativeDebugList = null,
    permission: ?*c.PiNodePermission = null,
    debug_call: c.PiNodeNativeDebugCall = undefined,
    debug_operations: c.PiNodePermissionDebug = undefined,
    trace: c.PiNodeEnvironmentTrace = std.mem.zeroes(c.PiNodeEnvironmentTrace),
    environment: c.PiNodePermissionEnvironment = undefined,
    before_permission: usize = 0,

    pub fn init(self: *Fixture, openssl: bool) !void {
        self.* = .{};
        self.runtime = c.pi_js_new_runtime(memory_limit, &self.memory) orelse return error.OutOfMemory;
        errdefer self.deinit();
        self.context = c.JS_NewContext(self.runtime.?) orelse return error.OutOfMemory;
        try self.paths_storage.init(self.memory, c.pi_node_environment_paths_storage_size(),
            c.pi_node_environment_paths_storage_alignment());
        const args = [_]Span{span("native-debug-permission")};
        self.paths = c.pi_node_environment_paths_construct(self.paths_storage.pointer.?,
            self.memory, &args, args.len) orelse return error.MissingActualPaths;
        self.map = c.pi_node_environment_map_create(self.memory, self.context) orelse return error.MissingActualMap;
        try self.debug_storage.init(self.memory, c.pi_node_native_debug_storage_size(),
            c.pi_node_native_debug_storage_alignment());
        self.debug_list = c.pi_node_native_debug_construct(self.debug_storage.pointer.?,
            @intFromBool(openssl)) orelse return error.MissingActualDebugList;
        c.pi_node_native_debug_bind_permission(&self.debug_call, &self.debug_operations,
            self.debug_list.?, self.memory, self.context);
        self.environment = .{ .paths = self.paths, .map = self.map,
            .context = self.context, .trace = &self.trace,
            .process_debug = &self.debug_operations };
    }
    pub fn openPermission(self: *Fixture) !void {
        if (self.permission != null) return error.PermissionAlreadyConstructed;
        self.before_permission = self.used();
        try self.permission_storage.init(self.owner(), c.pi_node_permission_storage_size(),
            c.pi_node_permission_storage_alignment());
        errdefer self.permission_storage.deinit();
        self.permission = c.pi_node_permission_construct(self.permission_storage.pointer.?,
            self.owner()) orelse return error.MissingActualPermission;
    }
    pub fn closePermission(self: *Fixture) void {
        if (self.permission) |permission| {
            self.permission = null;
            c.pi_node_permission_destroy(permission);
        }
        self.permission_storage.deinit();
    }
    pub fn closeVm(self: *Fixture) void {
        if (self.context) |context| {
            self.context = null;
            // The initialized fixture owns these views while the VM is live.
            if (self.debug_list != null) {
                self.debug_call.context = null;
                self.environment.context = null;
            }
            c.JS_PiCancelExecutionTermination(self.runtime.?);
            while (c.JS_HasException(context))
                c.JS_FreeValue(context, c.JS_GetException(context));
            c.JS_FreeContext(context);
        }
        if (self.runtime) |runtime| {
            self.runtime = null;
            c.JS_FreeRuntime(runtime);
        }
    }
    pub fn releaseCallerMemory(self: *Fixture) void {
        if (self.memory) |memory| {
            self.memory = null;
            c.pi_js_release_memory_owner(memory);
        }
    }
    pub fn owner(self: *Fixture) ?*anyopaque {
        return self.memory orelse self.paths_storage.memory.?;
    }
    pub fn used(self: *Fixture) usize { return c.pi_js_native_memory_used(self.owner()); }
    pub fn parse(self: *Fixture, input: []const u8) void {
        c.pi_node_native_debug_parse_text(self.debug_list.?, self.owner(), input.ptr, input.len);
    }
    pub fn warmDebug(self: *Fixture) void { self.parse("category-not-present-anywhere"); }
    pub fn enabled(self: *Fixture, name: []const u8) !bool {
        const count = c.pi_node_native_debug_category_count(self.debug_list.?);
        for (0..count) |index| {
            if (std.mem.eql(u8, std.mem.span(c.pi_node_native_debug_category_name(self.debug_list.?, index)), name))
                return c.pi_node_native_debug_enabled(self.debug_list.?, index) != 0;
        }
        return error.DebugCategoryNotFound;
    }
    pub fn countEnabled(self: *Fixture) usize {
        var count: usize = 0;
        for (0..c.pi_node_native_debug_category_count(self.debug_list.?)) |index|
            count += @intFromBool(c.pi_node_native_debug_enabled(self.debug_list.?, index) != 0);
        return count;
    }
    pub fn setEnv(self: *Fixture, key: []const u8, bytes: []const u8) void {
        c.pi_node_environment_map_lock(self.map.?);
        defer c.pi_node_environment_map_unlock(self.map.?);
        c.pi_node_environment_map_set_locked(self.map.?, key.ptr, key.len, bytes.ptr, bytes.len);
    }
    pub fn apply(self: *Fixture, scope: c_int, entries: []const Span) void {
        c.pi_node_permission_apply(self.permission.?, self.owner(), &self.environment,
            entries.ptr, entries.len, scope);
    }
    pub fn granted(self: *Fixture, scope: c_int, resource: []const u8) bool {
        return c.pi_node_permission_is_granted(self.permission.?, self.owner(),
            &self.environment, scope, resource.ptr, resource.len) != 0;
    }
    pub fn closeEnvironment(self: *Fixture) void {
        if (self.debug_list) |list| {
            self.debug_list = null;
            c.pi_node_native_debug_destroy(list);
        }
        self.debug_storage.deinit();
        if (self.map) |map| {
            self.map = null;
            c.pi_node_environment_map_release(map);
        }
        if (self.paths) |paths| {
            self.paths = null;
            c.pi_node_environment_paths_destroy(paths);
        }
        self.paths_storage.deinit();
    }
    pub fn deinit(self: *Fixture) void {
        self.closePermission();
        self.closeEnvironment();
        self.closeVm();
        self.releaseCallerMemory();
    }
};
pub fn span(bytes: []const u8) Span { return .{ .data = bytes.ptr, .length = bytes.len }; }
pub const Capture = struct {
    bytes: [8192]u8 = undefined,
    length: usize = 0,
    calls: usize = 0,
    overflow: bool = false,
    memory: ?*anyopaque = null,
    used_during: usize = 0,
    pub fn receive(raw: ?*anyopaque, bytes: [*c]const u8, length: usize) callconv(.c) void {
        const self: *Capture = @ptrCast(@alignCast(raw.?));
        self.calls += 1;
        if (self.memory != null) self.used_during = c.pi_js_native_memory_used(self.memory);
        if (length > self.bytes.len) { self.overflow = true; return; }
        self.length = length;
        @memcpy(self.bytes[0..length], bytes[0..length]);
    }
    pub fn expect(self: *const Capture, expected: []const u8) !void {
        try std.testing.expect(!self.overflow);
        try std.testing.expectEqual(@as(usize, 1), self.calls);
        try std.testing.expectEqualSlices(u8, expected, self.bytes[0..self.length]);
    }
};
pub fn expectOutput(output: *const c.PiNativeOutputObservation, bytes: []const u8) !void {
    try std.testing.expectEqual(@as(c_int, 0), output.io_error);
    try std.testing.expectEqual(@as(c_int, 0), output.overflow);
    try std.testing.expectEqualSlices(u8, bytes, output.bytes[0..output.length]);
}
pub const PermissionOperation = struct {
    fixture: *Fixture,
    scope: c_int,
    entries: []const Span,
    called: bool = false,
    pub fn run(raw: ?*anyopaque) callconv(.c) void {
        const self: *PermissionOperation = @ptrCast(@alignCast(raw.?));
        self.called = true;
        self.fixture.apply(self.scope, self.entries);
    }
};
pub const FormatOperation = struct {
    fixture: *Fixture,
    input: []const u8,
    capture: Capture = .{},
    called: bool = false,
    pub fn run(raw: ?*anyopaque) callconv(.c) void {
        const self: *FormatOperation = @ptrCast(@alignCast(raw.?));
        self.called = true;
        c.pi_native_debug_test_format(self.fixture.owner(), self.fixture.context, 0,
            self.input.ptr, self.input.len, "", Capture.receive, &self.capture);
    }
};

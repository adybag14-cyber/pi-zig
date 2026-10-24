//! Actual Module nearest-parent controls over native files, Permission, paths
//! and MapKVStore. Source only; Root owns any native build or runtime grant.
const std = @import("std");
const builtin = @import("builtin");
const a = @import("extensions/native_node_argument_values.zig");
const c = a.c;
const callbacks = @import("extensions/native_node_callback_scope.zig");
const providers = @import("extensions/native_node_async_providers.zig");
const templates = @import("extensions/native_node_async_wrap.zig");
const native = @import("extensions/native_node_async_wrap_state.zig");
const bindings = @import("extensions/native_node_modules_binding_data.zig");
const nearest = @import("extensions/native_node_module_nearest_parent.zig");
const functions = @import("extensions/native_node_module_callable.zig");
const support = @import("native_node_native_debug_test_support.zig");
const n = support.c;
const gpa = std.testing.allocator;

fn unselected(_: *callbacks.Environment) anyerror!void {
    return error.UnselectedNearestParentAsyncOperation;
}
fn unselectedCheck(_: *callbacks.Environment, _: callbacks.Check) anyerror {
    return error.UnselectedNearestParentNativeCheck;
}
fn unselectedCorruption(_: *callbacks.Environment, _: f64) anyerror {
    return error.UnselectedNearestParentAsyncCorruption;
}
const operations: callbacks.Operations = .{
    .on_hook_exception = unselected,
    .native_check_failure = unselectedCheck,
    .fail_corrupted_async_stack = unselectedCorruption,
    .perform_checkpoint = unselected,
    .schedule_destroy_immediate = unselected,
    .request_destroy_interrupt = unselected,
};

const Capture = struct {
    bytes: ?[:0]u8 = null,
    failed: bool = false,
    fn receive(raw: ?*anyopaque, bytes: [*c]const u8,
        length: usize) callconv(.c) void
    {
        const self: *Capture = @ptrCast(@alignCast(raw.?));
        self.bytes = gpa.dupeZ(u8, bytes[0..length]) catch {
            self.failed = true;
            return;
        };
    }
};
/// Actual native owners share this Engine's charged memory/context. Stable
/// fixture storage outlives all synchronous callbacks, including Error reentry.
const NativePolicy = struct {
    engine: *a.v.em.Engine = undefined,
    paths_storage: support.Storage = .{},
    debug_storage: support.Storage = .{},
    permission_storage: support.Storage = .{},
    paths: ?*n.PiNodeEnvironmentPaths = null,
    map: ?*n.PiNodeEnvironmentMap = null,
    debug_list: ?*n.PiNodeNativeDebugList = null,
    permission: ?*n.PiNodePermission = null,
    debug_call: n.PiNodeNativeDebugCall = undefined,
    debug_operations: n.PiNodePermissionDebug = undefined,
    trace: n.PiNodeEnvironmentTrace = std.mem.zeroes(n.PiNodeEnvironmentTrace),
    environment: n.PiNodePermissionEnvironment = undefined,

    fn init(self: *NativePolicy, engine: *a.v.em.Engine) !void {
        self.* = .{ .engine = engine };
        errdefer self.deinit();
        const memory = engine.native_memory_owner;
        const context: ?*n.JSContext = @ptrCast(engine.context);
        try self.paths_storage.init(memory, n.pi_node_environment_paths_storage_size(),
            n.pi_node_environment_paths_storage_alignment());
        const args = [_]n.PiNodeEnvironmentPathSpan{support.span("native-module-nearest")};
        self.paths = n.pi_node_environment_paths_construct(self.paths_storage.pointer.?,
            memory, &args, args.len) orelse return error.ActualPathsRequired;
        self.map = n.pi_node_environment_map_create(memory, context) orelse
            return error.ActualPrivateMapRequired;
        try self.debug_storage.init(memory, n.pi_node_native_debug_storage_size(),
            n.pi_node_native_debug_storage_alignment());
        self.debug_list = n.pi_node_native_debug_construct(self.debug_storage.pointer.?, 0)
            orelse return error.ActualDebugListRequired;
        n.pi_node_native_debug_bind_permission(&self.debug_call, &self.debug_operations,
            self.debug_list.?, memory, context);
        self.environment = .{ .paths = self.paths, .map = self.map,
            .context = context, .trace = &self.trace,
            .process_debug = &self.debug_operations };
        try self.permission_storage.init(memory, n.pi_node_permission_storage_size(),
            n.pi_node_permission_storage_alignment());
        self.permission = n.pi_node_permission_construct(self.permission_storage.pointer.?,
            memory) orelse return error.ActualPermissionRequired;
    }
    fn inputs(self: *NativePolicy) nearest.NativeInputs {
        return .{ .permission = @ptrCast(self.permission.?),
            .environment = @ptrCast(&self.environment) };
    }
    fn enable(self: *NativePolicy) void {
        n.pi_node_permission_enable(self.permission.?);
    }
    fn allow(self: *NativePolicy, path: []const u8) void {
        const entries = [_]n.PiNodeEnvironmentPathSpan{support.span(path)};
        n.pi_node_permission_apply(self.permission.?, self.engine.native_memory_owner,
            &self.environment, &entries, entries.len, n.PI_NODE_PERMISSION_FS_READ);
    }
    fn namespaced(self: *NativePolicy, path: []const u8) ![:0]u8 {
        var captured: Capture = .{};
        const input = support.span(path);
        n.pi_node_environment_path_to_namespaced(self.paths.?,
            self.engine.native_memory_owner, @ptrCast(self.engine.context),
            self.map.?, &self.trace, &input, Capture.receive, &captured);
        if (captured.failed) return error.OutOfMemory;
        return captured.bytes orelse return error.ActualPathCaptureRequired;
    }
    fn setEnv(self: *NativePolicy, key: []const u8, value: []const u8) void {
        n.pi_node_environment_map_lock(self.map.?);
        defer n.pi_node_environment_map_unlock(self.map.?);
        n.pi_node_environment_map_set_locked(self.map.?,
            key.ptr, key.len, value.ptr, value.len);
    }
    fn deinit(self: *NativePolicy) void {
        if (self.permission) |value| {
            self.permission = null;
            n.pi_node_permission_destroy(value);
        }
        self.permission_storage.deinit();
        if (self.debug_list) |value| {
            self.debug_list = null;
            n.pi_node_native_debug_destroy(value);
        }
        self.debug_storage.deinit();
        if (self.map) |value| {
            self.map = null;
            n.pi_node_environment_map_release(value);
        }
        if (self.paths) |value| {
            self.paths = null;
            n.pi_node_environment_paths_destroy(value);
        }
        self.paths_storage.deinit();
    }
};

const Disk = struct {
    temporary: std.testing.TmpDir,
    root: []u8,
    fn init() !Disk {
        var temporary = std.testing.tmpDir(.{});
        errdefer temporary.cleanup();
        var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const count = try temporary.dir.realPath(std.testing.io, &buffer);
        return .{ .temporary = temporary, .root = try gpa.dupe(u8, buffer[0..count]) };
    }
    fn path(self: *Disk, relative: []const u8) ![]u8 {
        return std.fs.path.join(gpa, &.{self.root, relative});
    }
    fn directory(self: *Disk, relative: []const u8) !void {
        try self.temporary.dir.createDirPath(std.testing.io, relative);
    }
    fn write(self: *Disk, relative: []const u8, contents: []const u8) !void {
        if (std.fs.path.dirname(relative)) |directory_name| try self.directory(directory_name);
        try self.temporary.dir.writeFile(std.testing.io,
            .{ .sub_path = relative, .data = contents });
    }
    fn deinit(self: *Disk) void {
        gpa.free(self.root);
        self.temporary.cleanup();
    }
};

var active: ?*Fixture = null;
const Fixture = struct {
    native_environment: std.process.Environ.Map,
    engine: *a.v.em.Engine = undefined,
    engine_alive: bool = false,
    policy: NativePolicy = .{},
    policy_alive: bool = false,
    environment: ?*callbacks.Environment = null,
    template_owner: c.JSValue = undefined,
    target: c.JSValue = undefined,
    data: ?*bindings.BindingData = null,
    roots: [2]c.JSValue = undefined,
    root_count: usize = 0,
    disk: *Disk,
    repair_saw_empty_cache: bool = false,

    fn init(self: *Fixture, disk: *Disk) !void {
        self.* = .{ .native_environment = .init(gpa), .disk = disk };
        errdefer self.deinit();
        self.engine = try a.v.em.Engine.init(gpa, .{});
        self.engine_alive = true;
        try @import("extensions/native_process.zig").install(
            self.engine, std.testing.io, &self.native_environment, &.{"native-module-nearest"});
        try self.policy.init(self.engine);
        self.policy_alive = true;
        active = self;
        const ignored = try a.expression(self.engine, bootstrap, .{self});
        self.engine.freeValue(ignored);
    }
    fn keep(self: *Fixture, value: c.JSValue) c.JSValue {
        std.debug.assert(self.root_count < self.roots.len);
        self.roots[self.root_count] = value;
        self.root_count += 1;
        return value;
    }
    fn bootstrap(s: *a.Scope, self: *Fixture) !c.JSValue {
        const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
        const generation = try s.beforeAllocation();
        const symbol = try s.checkedAllocation(
            c.JS_NewSymbol(s.engine.context, "node:resource_symbol", false), generation);
        const environment = try callbacks.Environment.create(s.engine, .{
            .provider_names = providers.names(false), .resource_symbol = symbol,
            .process_object = try s.get(global, "process"),
            .async_context_frame = true, .operations = operations,
        });
        self.environment = environment;
        environment.markBootstrapComplete();
        self.template_owner = self.keep(try templates.acquire(s.engine, environment));
        const shape = try bindings.TargetTemplate.create(s);
        const object_prototype = try s.get(try s.get(global, "Object"), "prototype");
        self.target = self.keep(a.duplicate(s.engine, try shape.newInstance(s, object_prototype)));
        self.data = try bindings.BindingData.create(s, shape, self.target, self.template_owner);
        const read = try s.own(try functions.create(s.engine, "actualNearest", 1,
            false, readCallback, &.{}));
        const read_type = try s.own(try functions.create(s.engine, "actualNearestType", 1,
            false, typeCallback, &.{}));
        const repair = try s.own(try functions.create(s.engine, "actualNearestRepair", 0,
            false, repairCallback, &.{}));
        try s.define(global, "actualNearest", read, c.JS_PROP_C_W_E);
        try s.define(global, "actualNearestType", read_type, c.JS_PROP_C_W_E);
        try s.define(global, "actualNearestRepair", repair, c.JS_PROP_C_W_E);
        return c.pi_js_undefined();
    }
    fn registry(self: *Fixture) !*native.Registry {
        return templates.registry(self.engine, self.template_owner);
    }
    fn readCallback(engine: *a.v.em.Engine, _: c.JSValue, args: []const c.JSValue,
        _: []const c.JSValue) !c.JSValue
    {
        const self = active orelse return error.ActualNearestFixtureRequired;
        if (self.engine != engine) return error.ActualNearestFixtureMismatch;
        return nearest.getNearestParentPackageJSON(engine,
            try self.registry(), self.policy.inputs(), args);
    }
    fn typeCallback(engine: *a.v.em.Engine, _: c.JSValue, args: []const c.JSValue,
        _: []const c.JSValue) !c.JSValue
    {
        const self = active orelse return error.ActualNearestFixtureRequired;
        if (self.engine != engine) return error.ActualNearestFixtureMismatch;
        return nearest.getNearestParentPackageJSONType(engine,
            try self.registry(), self.policy.inputs(), args);
    }
    fn repairCallback(engine: *a.v.em.Engine, _: c.JSValue, _: []const c.JSValue,
        _: []const c.JSValue) !c.JSValue
    {
        const self = active orelse return error.ActualNearestFixtureRequired;
        if (self.engine != engine) return error.ActualNearestFixtureMismatch;
        self.repair_saw_empty_cache = self.data.?.packageCache().entries.count() == 0;
        try self.disk.write("child/package.json", "{\"name\":\"repaired\",\"type\":\"commonjs\"}");
        return c.pi_js_undefined();
    }
    fn text(self: *Fixture, name: [*:0]const u8, bytes: []const u8) !void {
        const ignored = try a.expression(self.engine, struct {
            fn run(s: *a.Scope, key: [*:0]const u8, value: []const u8) !c.JSValue {
                const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
                try s.define(global, key, try s.text(value), c.JS_PROP_C_W_E);
                return c.pi_js_undefined();
            }
        }.run, .{name, bytes});
        self.engine.freeValue(ignored);
    }
    fn path(self: *Fixture, name: [*:0]const u8, relative: []const u8) !void {
        const absolute = try self.disk.path(relative);
        defer gpa.free(absolute);
        try self.text(name, absolute);
    }
    fn evaluate(self: *Fixture, source: []const u8) !void {
        const value = try self.engine.eval(source, "native-module-nearest.js", c.JS_EVAL_TYPE_GLOBAL);
        self.engine.freeValue(value);
    }
    fn expect(self: *Fixture, source: []const u8) !void {
        const value = try self.engine.eval(source, "native-module-nearest.js", c.JS_EVAL_TYPE_GLOBAL);
        defer self.engine.freeValue(value);
        try std.testing.expect(c.JS_ToBool(self.engine.context, value) == 1);
    }
    fn deinit(self: *Fixture) void {
        if (self.environment) |environment| {
            environment.can_call_into_js = false;
            environment.cleanupRealmAfterIoJoin() catch @panic("nearest Realm cleanup failed");
            self.data = null;
            environment.disarm() catch @panic("nearest Environment disarm failed");
            self.environment = null;
            environment.release();
        }
        if (self.policy_alive) {
            self.policy.deinit();
            self.policy_alive = false;
        }
        if (self.engine_alive) {
            while (self.root_count != 0) {
                self.root_count -= 1;
                self.engine.freeValue(self.roots[self.root_count]);
            }
            self.engine.deinit();
            self.engine_alive = false;
        }
        if (active == self) active = null;
        self.native_environment.deinit();
    }
};

test "native module nearest returns closest native Config as fresh intrinsic arrays and a direct type" {
    var disk = try Disk.init(); defer disk.deinit();
    try disk.write("package.json", "{\"name\":\"outer\",\"type\":\"commonjs\"}");
    try disk.write("pkg/lib/package.json", "{\"name\":\"closest\",\"type\":\"module\"}");
    var f: Fixture = undefined; try f.init(&disk); defer f.deinit();
    try f.path("actualPath", "pkg/lib/entry.js");
    const package = try disk.path("pkg/lib/package.json"); defer gpa.free(package);
    const expected = try f.policy.namespaced(package); defer gpa.free(expected);
    try f.text("expectedPackage", expected);
    try f.evaluate(
        \\globalThis.first = actualNearest(actualPath);
        \\globalThis.savedArrayPrototype = Array.prototype;
        \\globalThis.publicCalls = 0;
        \\globalThis.Array = function() { publicCalls++; throw 1; };
        \\JSON.parse = function() { publicCalls++; throw 2; };
        \\process.cwd = function() { publicCalls++; throw 3; };
        \\Object.defineProperty(savedArrayPrototype, "0", {
        \\  configurable: true, set() { publicCalls++; throw 4; }
        \\});
        \\globalThis.second = actualNearest(actualPath);
        \\delete savedArrayPrototype[0];
        \\first[0] = "mutated";
    );
    try f.expect(
        \\second !== first && second.length === 6 && second[0] === "closest" &&
        \\second[2] === "module" && second[5] === expectedPackage &&
        \\Object.getPrototypeOf(second) === savedArrayPrototype && publicCalls === 0 &&
        \\Object.getOwnPropertyDescriptor(second, "0").value === "closest" &&
        \\actualNearestType(actualPath) === "module"
    );
    try std.testing.expectEqual(@as(u32, 1), f.data.?.packageCache().entries.count());
}

test "native module nearest restores only the native trailing separator before the first parent" {
    var disk = try Disk.init(); defer disk.deinit();
    try disk.write("package.json", "{\"name\":\"outer\"}");
    try disk.write("child/package.json", "{\"name\":\"child\"}");
    var f: Fixture = undefined; try f.init(&disk); defer f.deinit();
    const child = try disk.path("child"); defer gpa.free(child);
    try f.text("plainPath", child);
    const native_tail = try std.fmt.allocPrint(gpa, "{s}{s}",
        .{child, if (builtin.os.tag == .windows) "\\" else "/"});
    defer gpa.free(native_tail);
    try f.text("nativeTail", native_tail);
    const forward_tail = try std.fmt.allocPrint(gpa, "{s}/", .{child});
    defer gpa.free(forward_tail);
    try f.text("forwardTail", forward_tail);
    try f.expect("actualNearest(plainPath)[0] === 'outer' && actualNearest(nativeTail)[0] === 'child'");
    if (builtin.os.tag == .windows)
        try f.expect("actualNearest(forwardTail)[0] === 'outer'")
    else
        try f.expect("actualNearest(forwardTail)[0] === 'child'");
}

test "native module nearest stops at node_modules before probing that package or any ancestor" {
    var disk = try Disk.init(); defer disk.deinit();
    try disk.write("package.json", "{\"name\":\"must-not-read\"}");
    try disk.write("node_modules/package.json", "{\"name\":false}");
    var f: Fixture = undefined; try f.init(&disk); defer f.deinit();
    try f.path("actualPath", "node_modules/entry.js");
    try f.expect("actualNearest(actualPath) === undefined && actualNearestType(actualPath) === undefined");
    try std.testing.expectEqual(@as(u32, 0), f.data.?.packageCache().entries.count());
}

test "native module nearest enabled native Permission denies before even a cached package is returned" {
    var disk = try Disk.init(); defer disk.deinit();
    try disk.write("pkg/package.json", "{\"name\":\"cached\",\"type\":\"module\"}");
    var f: Fixture = undefined; try f.init(&disk); defer f.deinit();
    try f.path("actualPath", "pkg/entry.js");
    try f.expect("actualNearest(actualPath)[0] === 'cached'");
    f.policy.enable(); // Genuine native default FS policy now denies this path.
    try f.expect("actualNearest(actualPath) === undefined && actualNearestType(actualPath) === undefined");
    try std.testing.expectEqual(@as(u32, 1), f.data.?.packageCache().entries.count());
}

test "native module nearest permits an actual subtree then stops before reading a denied ancestor" {
    var disk = try Disk.init(); defer disk.deinit();
    try disk.write("package.json", "{\"name\":\"denied-ancestor\"}");
    try disk.directory("allowed");
    var f: Fixture = undefined; try f.init(&disk); defer f.deinit();
    const allowed = try disk.path("allowed"); defer gpa.free(allowed);
    f.policy.enable();
    f.policy.allow(allowed);
    try f.path("actualPath", "allowed/entry.js");
    try f.expect("actualNearest(actualPath) === undefined");
    try std.testing.expectEqual(@as(u32, 1), f.data.?.packageCache().entries.count());
    const missing = try disk.path("allowed/package.json"); defer gpa.free(missing);
    const normalized = try f.policy.namespaced(missing); defer gpa.free(normalized);
    const entry = f.data.?.packageCache().entries.get(normalized);
    try std.testing.expect(entry != null and entry.? == null);
}

test "native module nearest keeps a negative child read cached when that physical file appears" {
    var disk = try Disk.init(); defer disk.deinit();
    try disk.write("package.json", "{\"name\":\"outer\"}");
    try disk.directory("child");
    var f: Fixture = undefined; try f.init(&disk); defer f.deinit();
    try f.path("actualPath", "child/entry.js");
    try f.expect("actualNearest(actualPath)[0] === 'outer'");
    try disk.write("child/package.json", "{\"name\":\"new-child\"}");
    try f.expect("actualNearest(actualPath)[0] === 'outer'");
    try std.testing.expectEqual(@as(u32, 2), f.data.?.packageCache().entries.count());
}

test "native module nearest invalid Config stays uncached through native Error setter reentry" {
    var disk = try Disk.init(); defer disk.deinit();
    try disk.write("package.json", "{\"name\":\"must-not-read\"}");
    try disk.write("child/package.json", "{\"name\":false}");
    var f: Fixture = undefined; try f.init(&disk); defer f.deinit();
    const child = try disk.path("child"); defer gpa.free(child);
    f.policy.enable();
    f.policy.allow(child);
    try f.path("actualPath", "child/entry.js");
    const package = try disk.path("child/package.json"); defer gpa.free(package);
    const expected = try f.policy.namespaced(package); defer gpa.free(expected);
    try f.text("expectedPackage", expected);
    try f.evaluate(
        \\globalThis.NativeError = Error;
        \\globalThis.Error = function() { throw "public Error selected"; };
        \\Object.defineProperty(NativeError.prototype, "code", {
        \\  configurable: true, set(value) {
        \\    globalThis.setterError = this;
        \\    globalThis.setterCode = value;
        \\    actualNearestRepair();
        \\    globalThis.nested = actualNearest(actualPath);
        \\  }
        \\});
        \\try { actualNearest(actualPath); }
        \\catch (error) { globalThis.outerError = error; }
        \\delete NativeError.prototype.code;
    );
    try f.expect(
        \\outerError === setterError && Object.getPrototypeOf(outerError) === NativeError.prototype &&
        \\setterCode === "ERR_INVALID_PACKAGE_CONFIG" &&
        \\outerError.message === "Invalid package config " + expectedPackage + "." &&
        \\nested[0] === "repaired" && actualNearestType(actualPath) === "commonjs"
    );
    try std.testing.expect(f.repair_saw_empty_cache);
    try std.testing.expectEqual(@as(u32, 1), f.data.?.packageCache().entries.count());
}

test "native module nearest namespace leaf uses actual private drive Map and preserves native POSIX spelling" {
    var disk = try Disk.init(); defer disk.deinit();
    var f: Fixture = undefined; try f.init(&disk); defer f.deinit();
    if (builtin.os.tag == .windows) {
        try std.testing.expect(n.pi_node_options_environment_allowed() != 0);
        f.policy.setEnv("=Q:", "Q:\\actual-private-map");
        const drive = try f.policy.namespaced("Q:child\\entry.js"); defer gpa.free(drive);
        try std.testing.expectEqualStrings("\\\\?\\Q:\\actual-private-map\\child\\entry.js", drive);
        const unc = try f.policy.namespaced("//server/share/pkg/../entry.js"); defer gpa.free(unc);
        try std.testing.expectEqualStrings("\\\\?\\UNC\\server\\share\\entry.js", unc);
    } else {
        const input = "/pkg//nested/../entry.js";
        const result = try f.policy.namespaced(input); defer gpa.free(result);
        try std.testing.expectEqualStrings(input, result);
    }
    const empty = try f.policy.namespaced(""); defer gpa.free(empty);
    try std.testing.expectEqualStrings("", empty);
    try f.expect("actualNearest('') === undefined && actualNearestType('') === undefined");
    try std.testing.expectEqual(@as(u32, 0), f.data.?.packageCache().entries.count());
}

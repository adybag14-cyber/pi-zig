//! Actual private CommonJS package-read controls over native physical files,
//! Permission and intrinsic access Errors. Source only; Root owns execution.
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
const commonjs = @import("extensions/native_node_module_commonjs_read.zig");
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
    permission_keys: commonjs.PermissionKeys = undefined,
    roots: [4]c.JSValue = undefined,
    root_count: usize = 0,
    disk: *Disk,

    fn init(self: *Fixture, disk: *Disk) !void {
        self.* = .{ .native_environment = .init(gpa), .disk = disk };
        errdefer self.deinit();
        self.engine = try a.v.em.Engine.init(gpa, .{});
        self.engine_alive = true;
        try @import("extensions/native_process.zig").install(
            self.engine, std.testing.io, &self.native_environment, &.{"native-module-commonjs-read"});
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
        // Actual primitive native Environment keys, rooted before publication.
        self.permission_keys = try commonjs.PermissionKeys.create(s);
        self.permission_keys.permission = self.keep(a.duplicate(s.engine, self.permission_keys.permission));
        self.permission_keys.resource = self.keep(a.duplicate(s.engine, self.permission_keys.resource));
        const read = try s.own(try functions.create(s.engine, "actualCommonJSRead", 1,
            false, readCallback, &.{}));
        const allow = try s.own(try functions.create(s.engine, "actualCommonJSAllowRoot", 0,
            false, allowCallback, &.{}));
        try s.define(global, "actualCommonJSRead", read, c.JS_PROP_C_W_E);
        try s.define(global, "actualCommonJSAllowRoot", allow, c.JS_PROP_C_W_E);
        return c.pi_js_undefined();
    }
    fn registry(self: *Fixture) !*native.Registry {
        return templates.registry(self.engine, self.template_owner);
    }
    fn readCallback(engine: *a.v.em.Engine, _: c.JSValue, args: []const c.JSValue,
        _: []const c.JSValue) !c.JSValue
    {
        const self = active orelse return error.ActualCommonJSReadFixtureRequired;
        if (self.engine != engine) return error.ActualCommonJSReadFixtureMismatch;
        return commonjs.readCommonJSPackageJSON(engine,
            try self.registry(), self.policy.inputs(), self.permission_keys, args);
    }
    fn allowCallback(engine: *a.v.em.Engine, _: c.JSValue, _: []const c.JSValue,
        _: []const c.JSValue) !c.JSValue
    {
        const self = active orelse return error.ActualCommonJSReadFixtureRequired;
        if (self.engine != engine) return error.ActualCommonJSReadFixtureMismatch;
        self.policy.allow(self.disk.root);
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
    fn expected(self: *Fixture, relative: []const u8) !void {
        const absolute = try self.disk.path(relative); defer gpa.free(absolute);
        const normalized = try self.policy.namespaced(absolute); defer gpa.free(normalized);
        try self.text("expectedPackage", normalized);
    }
    fn evaluate(self: *Fixture, source: []const u8) !void {
        const value = try self.engine.eval(source, "native-module-commonjs-read.js", c.JS_EVAL_TYPE_GLOBAL);
        self.engine.freeValue(value);
    }
    fn expect(self: *Fixture, source: []const u8) !void {
        const value = try self.engine.eval(source, "native-module-commonjs-read.js", c.JS_EVAL_TYPE_GLOBAL);
        defer self.engine.freeValue(value);
        try std.testing.expect(c.JS_ToBool(self.engine.context, value) == 1);
    }
    fn deinit(self: *Fixture) void {
        if (self.environment) |environment| {
            environment.can_call_into_js = false;
            environment.cleanupRealmAfterIoJoin() catch @panic("CommonJS read Realm cleanup failed");
            self.data = null;
            environment.disarm() catch @panic("CommonJS read Environment disarm failed");
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

test "native module CommonJS read uses actual permission and namespace with fresh intrinsic cached results" {
    var disk = try Disk.init(); defer disk.deinit();
    try disk.write("package.json", "{\"name\":\"original\",\"type\":\"module\",\"exports\":{\".\":\"./entry.js\"}}");
    var f: Fixture = undefined; try f.init(&disk); defer f.deinit();
    f.policy.enable();
    f.policy.allow(disk.root);
    try f.path("actualTarget", "package.json");
    try f.expected("package.json");
    try f.evaluate("globalThis.first = actualCommonJSRead(actualTarget)");
    try disk.write("package.json", "{\"name\":false}");
    try f.evaluate(
        \\globalThis.savedArrayPrototype = Array.prototype;
        \\globalThis.publicCalls = 0;
        \\globalThis.Array = function() { publicCalls++; throw 1; };
        \\JSON.parse = function() { publicCalls++; throw 2; };
        \\process.cwd = function() { publicCalls++; throw 3; };
        \\Object.defineProperty(savedArrayPrototype, "0", {
        \\  configurable: true, set() { publicCalls++; throw 4; }
        \\});
        \\globalThis.second = actualCommonJSRead(actualTarget);
        \\delete savedArrayPrototype[0];
        \\first[0] = "mutated";
    );
    try f.expect(
        \\second !== first && second.length === 6 && second[0] === "original" &&
        \\second[2] === "module" && second[4] === '{".":"./entry.js"}' &&
        \\second[5] === expectedPackage && Object.getPrototypeOf(second) === savedArrayPrototype &&
        \\Object.getOwnPropertyDescriptor(second, "0").value === "original" && publicCalls === 0
    );
    try std.testing.expectEqual(@as(u32, 1), f.data.?.packageCache().entries.count());
}

test "native module CommonJS read denied access uses intrinsic Error and full original resource before cache" {
    var disk = try Disk.init(); defer disk.deinit();
    try disk.write("package.json", "{\"name\":\"must-not-read\"}");
    var f: Fixture = undefined; try f.init(&disk); defer f.deinit();
    try f.path("actualTarget", "package.json");
    f.policy.enable();
    try f.evaluate(
        \\globalThis.NativeError = Error;
        \\globalThis.Error = function() { throw "public Error selected"; };
        \\try { actualCommonJSRead(actualTarget); } catch (error) { globalThis.denied = error; }
        \\try { actualCommonJSRead("raw\\name\0\uD800"); } catch (error) { globalThis.rawDenied = error; }
    );
    try f.expect(
        \\Object.getPrototypeOf(denied) === NativeError.prototype &&
        \\denied.code === "ERR_ACCESS_DENIED" && denied.permission === "FileSystemRead" &&
        \\denied.message === "Access to this API has been restricted. Use --allow-fs-read to manage permissions." &&
        \\denied.resource === actualTarget && rawDenied.resource === "raw\\name\0\uFFFD" &&
        \\Object.getOwnPropertyDescriptor(denied, "resource").enumerable === true &&
        \\Object.getOwnPropertyDescriptor(denied, "permission").writable === true &&
        \\Object.getOwnPropertyDescriptor(denied, "code").configurable === true
    );
    try std.testing.expectEqual(@as(u32, 0), f.data.?.packageCache().entries.count());
}

test "native module CommonJS read access Error setters reenter with actual permission change and stable inputs" {
    var disk = try Disk.init(); defer disk.deinit();
    try disk.write("package.json", "{\"name\":\"nested-actual-read\"}");
    var f: Fixture = undefined; try f.init(&disk); defer f.deinit();
    try f.path("actualTarget", "package.json");
    f.policy.enable();
    try f.evaluate(
        \\globalThis.NativeError = Error;
        \\globalThis.trace = "";
        \\globalThis.originalTarget = actualTarget;
        \\Object.defineProperty(NativeError.prototype, "code", {
        \\  configurable: true, set(value) {
        \\    trace += "code|"; globalThis.codeReceiver = this; globalThis.codeValue = value;
        \\  }
        \\});
        \\Object.defineProperty(NativeError.prototype, "permission", {
        \\  configurable: true, set(value) {
        \\    trace += "permission|"; globalThis.permissionReceiver = this;
        \\    globalThis.permissionValue = value; globalThis.actualTarget = "changed during setter";
        \\    actualCommonJSAllowRoot();
        \\    globalThis.nested = actualCommonJSRead(originalTarget);
        \\  }
        \\});
        \\Object.defineProperty(NativeError.prototype, "resource", {
        \\  configurable: true, set(value) {
        \\    trace += "resource"; globalThis.resourceReceiver = this; globalThis.resourceValue = value;
        \\  }
        \\});
        \\try { actualCommonJSRead(actualTarget); } catch (error) { globalThis.outerError = error; }
        \\delete NativeError.prototype.code;
        \\delete NativeError.prototype.permission;
        \\delete NativeError.prototype.resource;
    );
    try f.expect(
        \\trace === "code|permission|resource" && outerError === codeReceiver &&
        \\outerError === permissionReceiver && outerError === resourceReceiver &&
        \\codeValue === "ERR_ACCESS_DENIED" && permissionValue === "FileSystemRead" &&
        \\resourceValue === originalTarget && nested[0] === "nested-actual-read" &&
        \\actualCommonJSRead(originalTarget)[0] === "nested-actual-read"
    );
    try std.testing.expectEqual(@as(u32, 1), f.data.?.packageCache().entries.count());
}

test "native module CommonJS read permission setter exception supersedes denial and skips resource Set" {
    var disk = try Disk.init(); defer disk.deinit();
    try disk.write("package.json", "{}");
    var f: Fixture = undefined; try f.init(&disk); defer f.deinit();
    try f.path("actualTarget", "package.json");
    f.policy.enable();
    try f.evaluate(
        \\globalThis.reason = {};
        \\globalThis.resourceCalls = 0;
        \\Object.defineProperty(Error.prototype, "permission", {
        \\  configurable: true, set(value) { globalThis.permissionValue = value; throw reason; }
        \\});
        \\Object.defineProperty(Error.prototype, "resource", {
        \\  configurable: true, set() { resourceCalls++; }
        \\});
        \\try { actualCommonJSRead(actualTarget); } catch (error) { globalThis.caught = error; }
        \\delete Error.prototype.permission;
        \\delete Error.prototype.resource;
    );
    try f.expect("caught === reason && permissionValue === 'FileSystemRead' && resourceCalls === 0");
    try std.testing.expectEqual(@as(u32, 0), f.data.?.packageCache().entries.count());
}

test "native module CommonJS read resource setter exception supersedes the completed permission Set" {
    var disk = try Disk.init(); defer disk.deinit();
    try disk.write("package.json", "{}");
    var f: Fixture = undefined; try f.init(&disk); defer f.deinit();
    try f.path("actualTarget", "package.json");
    f.policy.enable();
    try f.evaluate(
        \\globalThis.reason = {};
        \\globalThis.trace = "";
        \\Object.defineProperty(Error.prototype, "permission", {
        \\  configurable: true, set(value) { trace += "permission|"; globalThis.permissionValue = value; }
        \\});
        \\Object.defineProperty(Error.prototype, "resource", {
        \\  configurable: true, set(value) {
        \\    trace += "resource"; globalThis.resourceValue = value; throw reason;
        \\  }
        \\});
        \\try { actualCommonJSRead(actualTarget); } catch (error) { globalThis.caught = error; }
        \\delete Error.prototype.permission;
        \\delete Error.prototype.resource;
    );
    try f.expect(
        \\caught === reason && trace === "permission|resource" &&
        \\permissionValue === "FileSystemRead" && resourceValue === actualTarget
    );
    try std.testing.expectEqual(@as(u32, 0), f.data.?.packageCache().entries.count());
}

test "native module CommonJS read accepts nonthrowing false native code permission and resource Sets" {
    var disk = try Disk.init(); defer disk.deinit();
    try disk.write("package.json", "{}");
    var f: Fixture = undefined; try f.init(&disk); defer f.deinit();
    try f.path("actualTarget", "package.json");
    f.policy.enable();
    try f.evaluate(
        \\for (const key of ["code", "permission", "resource"])
        \\  Object.defineProperty(Error.prototype, key, {
        \\    configurable: true, writable: false, value: "inherited-" + key
        \\  });
        \\try { actualCommonJSRead(actualTarget); } catch (error) {
        \\  globalThis.caught = error;
        \\  globalThis.inherited = [error.code, error.permission, error.resource];
        \\}
        \\for (const key of ["code", "permission", "resource"]) delete Error.prototype[key];
    );
    try f.expect(
        \\caught instanceof Error && inherited.join("|") === "inherited-code|inherited-permission|inherited-resource" &&
        \\Object.getOwnPropertyDescriptor(caught, "code") === undefined &&
        \\Object.getOwnPropertyDescriptor(caught, "permission") === undefined &&
        \\Object.getOwnPropertyDescriptor(caught, "resource") === undefined &&
        \\caught.message === "Access to this API has been restricted. Use --allow-fs-read to manage permissions."
    );
    try std.testing.expectEqual(@as(u32, 0), f.data.?.packageCache().entries.count());
}

test "native module CommonJS read retains negative exact-path cache after the physical file appears" {
    var disk = try Disk.init(); defer disk.deinit();
    try disk.write("package.json", "{\"name\":\"parent-must-not-be-read\"}");
    try disk.directory("child");
    var f: Fixture = undefined; try f.init(&disk); defer f.deinit();
    f.policy.enable();
    f.policy.allow(disk.root);
    try f.path("actualTarget", "child/explicit.json");
    try f.expect("actualCommonJSRead(actualTarget) === undefined");
    try disk.write("child/explicit.json", "{\"name\":\"now-present\"}");
    try f.expect("actualCommonJSRead(actualTarget) === undefined");
    try std.testing.expectEqual(@as(u32, 1), f.data.?.packageCache().entries.count());
}

test "native module CommonJS read allowed invalid package uses native context-free error and remains repairable" {
    var disk = try Disk.init(); defer disk.deinit();
    try disk.write("package.json", "{\"name\":false}");
    var f: Fixture = undefined; try f.init(&disk); defer f.deinit();
    f.policy.enable();
    f.policy.allow(disk.root);
    try f.path("actualTarget", "package.json");
    try f.expected("package.json");
    try f.evaluate(
        \\globalThis.NativeError = Error;
        \\globalThis.Error = function() { throw "public Error selected"; };
        \\try { actualCommonJSRead(actualTarget); } catch (error) { globalThis.caught = error; }
    );
    try f.expect(
        \\Object.getPrototypeOf(caught) === NativeError.prototype &&
        \\caught.code === "ERR_INVALID_PACKAGE_CONFIG" &&
        \\caught.message === "Invalid package config " + expectedPackage + "." &&
        \\Object.getOwnPropertyDescriptor(caught, "permission") === undefined &&
        \\Object.getOwnPropertyDescriptor(caught, "resource") === undefined
    );
    try std.testing.expectEqual(@as(u32, 0), f.data.?.packageCache().entries.count());
    try disk.write("package.json", "{\"name\":\"repaired\",\"type\":\"commonjs\"}");
    try f.expect("actualCommonJSRead(actualTarget)[0] === 'repaired' && actualCommonJSRead(actualTarget)[2] === 'commonjs'");
    try std.testing.expectEqual(@as(u32, 1), f.data.?.packageCache().entries.count());
}

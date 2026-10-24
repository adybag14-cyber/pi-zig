//! Actual modules::BindingData package-input controls over owned native files.
//! Authored source only; build, metadata and runtime require Root's separate
//! bounded grant. The test bridge calls the private normalized-path tail; it
//! does not stand in for public Module, permission or ESM URL assembly.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const c = a.c;
const callbacks = @import("extensions/native_node_callback_scope.zig");
const providers = @import("extensions/native_node_async_providers.zig");
const templates = @import("extensions/native_node_async_wrap.zig");
const native = @import("extensions/native_node_async_wrap_state.zig");
const bindings = @import("extensions/native_node_modules_binding_data.zig");
const values = @import("extensions/native_node_package_json_values.zig");
const paths = @import("extensions/native_node_package_path.zig");
const functions = @import("extensions/native_node_module_callable.zig");
const gpa = std.testing.allocator;

fn unselected(_: *callbacks.Environment) anyerror!void {
    return error.UnselectedPackageInputAsyncOperation;
}
fn unselectedCheck(_: *callbacks.Environment, _: callbacks.Check) anyerror {
    return error.UnselectedPackageInputNativeCheck;
}
fn unselectedCorruption(_: *callbacks.Environment, _: f64) anyerror {
    return error.UnselectedPackageInputAsyncCorruption;
}
const operations: callbacks.Operations = .{
    .on_hook_exception = unselected,
    .native_check_failure = unselectedCheck,
    .fail_corrupted_async_stack = unselectedCorruption,
    .perform_checkpoint = unselected,
    .schedule_destroy_immediate = unselected,
    .request_destroy_interrupt = unselected,
};

const Disk = struct {
    temporary: std.testing.TmpDir,
    path: [:0]u8,

    fn init() !Disk {
        var temporary = std.testing.tmpDir(.{});
        errdefer temporary.cleanup();
        const path = try namedPath(&temporary, "package.json");
        return .{ .temporary = temporary, .path = path };
    }
    fn namedPath(temporary: *std.testing.TmpDir, name: []const u8) ![:0]u8 {
        var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const count = try temporary.dir.realPath(std.testing.io, &buffer);
        const absolute = try std.fs.path.join(gpa, &.{buffer[0..count], name});
        defer gpa.free(absolute);
        const normalized = try paths.namespaced(gpa, absolute);
        defer gpa.free(normalized);
        return gpa.dupeZ(u8, normalized);
    }
    fn write(self: *Disk, contents: []const u8) !void {
        try self.temporary.dir.writeFile(std.testing.io,
            .{ .sub_path = "package.json", .data = contents });
    }
    fn deinit(self: *Disk) void {
        gpa.free(self.path);
        self.temporary.cleanup();
    }
};

var active: ?*Fixture = null;
const Fixture = struct {
    native_environment: std.process.Environ.Map,
    engine: *a.v.em.Engine = undefined,
    engine_alive: bool = false,
    environment: ?*callbacks.Environment = null,
    template_owner: c.JSValue = undefined,
    target: c.JSValue = undefined,
    data: ?*bindings.BindingData = null,
    roots: [4]c.JSValue = undefined,
    root_count: usize = 0,
    disk: *Disk,
    repair_saw_empty_cache: bool = false,
    realm_closed: bool = false,

    fn init(self: *Fixture, disk: *Disk) !void {
        self.* = .{ .native_environment = .init(gpa), .disk = disk };
        errdefer self.deinit();
        self.engine = try a.v.em.Engine.init(gpa, .{});
        self.engine_alive = true;
        try @import("extensions/native_process.zig").install(
            self.engine, std.testing.io, &self.native_environment, &.{"native-module-package-input"});
        active = self;
        const ignored = try a.expression(self.engine, bootstrap, .{self});
        self.engine.freeValue(ignored);
    }
    fn keep(self: *Fixture, owned: c.JSValue) c.JSValue {
        std.debug.assert(self.root_count < self.roots.len);
        self.roots[self.root_count] = owned;
        self.root_count += 1;
        return owned;
    }
    fn bootstrap(s: *a.Scope, self: *Fixture) !c.JSValue {
        const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
        const generation = try s.beforeAllocation();
        const resource_symbol = try s.checkedAllocation(
            c.JS_NewSymbol(s.engine.context, "node:resource_symbol", false), generation);
        const environment = try callbacks.Environment.create(s.engine, .{
            .provider_names = providers.names(false),
            .resource_symbol = resource_symbol,
            .process_object = try s.get(global, "process"),
            .async_context_frame = true,
            .operations = operations,
        });
        self.environment = environment;
        environment.markBootstrapComplete();
        self.template_owner = self.keep(try templates.acquire(s.engine, environment));
        const shape = try bindings.TargetTemplate.create(s);
        const object_prototype = try s.get(try s.get(global, "Object"), "prototype");
        self.target = self.keep(a.duplicate(s.engine, try shape.newInstance(s, object_prototype)));
        self.data = try bindings.BindingData.create(s, shape, self.target, self.template_owner);
        const read = try s.own(try functions.create(s.engine, "actualPackageRead", 1,
            false, readCallback, &.{}));
        const repair = try s.own(try functions.create(s.engine, "actualPackageRepair", 0,
            false, repairCallback, &.{}));
        try s.define(global, "actualPackageRead", read, c.JS_PROP_C_W_E);
        try s.define(global, "actualPackageRepair", repair, c.JS_PROP_C_W_E);
        try s.define(global, "actualPackagePath", try s.text(self.disk.path), c.JS_PROP_C_W_E);
        return c.pi_js_undefined();
    }
    fn registry(self: *Fixture) !*native.Registry {
        return templates.registry(self.engine, self.template_owner);
    }
    fn read(self: *Fixture, path: [:0]const u8) !c.JSValue {
        const data = bindings.get(try self.registry()) orelse
            return error.ActualPackageInputBindingRequired;
        return data.serializePackageJSON(self.engine, path);
    }
    fn readBody(s: *a.Scope, args: []const c.JSValue) !c.JSValue {
        const self = active orelse return error.ActualPackageInputFixtureRequired;
        if (self.engine != s.engine or args.len != 1 or !c.JS_IsString(args[0]))
            return error.ActualPackageInputStringRequired;
        const data = bindings.get(try self.registry()) orelse
            return error.ActualPackageInputBindingRequired;
        const allocator = data.packageCache().allocator();
        const path = try values.utf8(s, allocator, args[0]);
        defer allocator.free(path);
        return data.serializePackageJSON(s.engine, path);
    }
    fn readCallback(engine: *a.v.em.Engine, _: c.JSValue, args: []const c.JSValue,
        _: []const c.JSValue) !c.JSValue
    {
        return a.expression(engine, readBody, .{args});
    }
    fn repairCallback(engine: *a.v.em.Engine, _: c.JSValue, _: []const c.JSValue,
        _: []const c.JSValue) !c.JSValue
    {
        const self = active orelse return error.ActualPackageInputFixtureRequired;
        if (self.engine != engine) return error.ActualPackageInputFixtureMismatch;
        const data = bindings.get(try self.registry()) orelse
            return error.ActualPackageInputBindingRequired;
        self.repair_saw_empty_cache = data.packageCache().entries.count() == 0;
        try self.disk.write(
            "{\"name\":\"repaired\",\"main\":\"after.js\",\"exports\":{\"default\":\"./good.js\"}}");
        return c.pi_js_undefined();
    }
    fn evaluate(self: *Fixture, source: []const u8) !void {
        const result = try self.engine.eval(source, "native-module-package-input.js", c.JS_EVAL_TYPE_GLOBAL);
        self.engine.freeValue(result);
    }
    fn expect(self: *Fixture, source: []const u8) !void {
        const result = try self.engine.eval(source, "native-module-package-input.js", c.JS_EVAL_TYPE_GLOBAL);
        defer self.engine.freeValue(result);
        try std.testing.expect(c.JS_ToBool(self.engine.context, result) == 1);
    }
    fn expose(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        const ignored = try a.expression(self.engine, struct {
            fn run(s: *a.Scope, key: [*:0]const u8, item: c.JSValue) !c.JSValue {
                const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
                try s.define(global, key, item, c.JS_PROP_C_W_E);
                return c.pi_js_undefined();
            }
        }.run, .{name, value});
        self.engine.freeValue(ignored);
    }
    fn closeRealm(self: *Fixture) !void {
        if (self.realm_closed) return;
        const environment = self.environment orelse return;
        environment.can_call_into_js = false;
        try environment.cleanupRealmAfterIoJoin();
        self.data = null;
        self.realm_closed = true;
    }
    fn deinit(self: *Fixture) void {
        if (self.environment) |environment| {
            self.closeRealm() catch @panic("package input realm cleanup failed");
            environment.disarm() catch @panic("package input environment disarm failed");
            self.environment = null;
            environment.release();
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

test "native module package input returns fresh intrinsic arrays from one physical cached Config" {
    var disk = try Disk.init(); defer disk.deinit();
    try disk.write("{\"name\":\"original\",\"main\":\"entry.js\",\"type\":\"module\",\"imports\":{\"#x\":\"./x.js\"},\"exports\":[\"./entry.js\"]}");
    var f: Fixture = undefined; try f.init(&disk); defer f.deinit();
    const first = try f.read(disk.path); defer f.engine.freeValue(first);
    try f.expose("first", first);
    // A changed physical file is not reparsed once this native key is cached.
    try disk.write("{\"name\":false}");
    try f.evaluate(
        \\globalThis.savedArrayPrototype = Array.prototype;
        \\globalThis.publicCalls = 0;
        \\globalThis.Array = function() { publicCalls++; throw 1; };
        \\globalThis.JSON.parse = function() { publicCalls++; throw 2; };
        \\Object.defineProperty(savedArrayPrototype, "0", {
        \\  configurable: true, set() { publicCalls++; throw 3; }
        \\});
        \\globalThis.second = actualPackageRead(actualPackagePath);
        \\delete savedArrayPrototype[0];
        \\first[0] = "mutated";
    );
    try f.expect(
        \\second !== first && second.length === 6 && second[0] === "original" &&
        \\second[1] === "entry.js" && second[2] === "module" &&
        \\second[3] === '{"#x":"./x.js"}' && second[4] === '["./entry.js"]' &&
        \\second[5] === actualPackagePath && publicCalls === 0 &&
        \\Object.getPrototypeOf(second) === savedArrayPrototype &&
        \\Object.getOwnPropertyDescriptor(second, "0").value === "original"
    );
    try std.testing.expectEqual(@as(u32, 1), f.data.?.packageCache().entries.count());
}

test "native module package input negative physical cache remains missing after the file appears" {
    var disk = try Disk.init(); defer disk.deinit();
    {
        var f: Fixture = undefined; try f.init(&disk); defer f.deinit();
        const missing = try f.read(disk.path); defer f.engine.freeValue(missing);
        try std.testing.expect(c.JS_IsUndefined(missing));
        try disk.write("{\"name\":\"now-present\"}");
        const still_missing = try f.read(disk.path); defer f.engine.freeValue(still_missing);
        try std.testing.expect(c.JS_IsUndefined(still_missing));
        const entry = f.data.?.packageCache().entries.get(disk.path);
        try std.testing.expect(entry != null and entry.? == null);
    }
    // A genuinely distinct native owner sees the new physical contents.
    var fresh: Fixture = undefined; try fresh.init(&disk); defer fresh.deinit();
    try fresh.expect("actualPackageRead(actualPackagePath)[0] === 'now-present'");
}

test "native module package input invalid Config stays uncached through native Error setter reentry" {
    var disk = try Disk.init(); defer disk.deinit();
    try disk.write("{\"name\":\"partial\",\"exports\":{\"x\":1},\"name\":false}");
    var f: Fixture = undefined; try f.init(&disk); defer f.deinit();
    try f.evaluate(
        \\globalThis.NativeError = Error;
        \\globalThis.Error = function() { throw "public Error selected"; };
        \\Object.defineProperty(NativeError.prototype, "code", {
        \\  configurable: true, set(value) {
        \\    globalThis.setterError = this;
        \\    globalThis.setterCode = value;
        \\    actualPackageRepair();
        \\    globalThis.nested = actualPackageRead(actualPackagePath);
        \\  }
        \\});
        \\try { actualPackageRead(actualPackagePath); }
        \\catch (error) { globalThis.outerError = error; }
        \\delete NativeError.prototype.code;
    );
    try f.expect(
        \\outerError === setterError && Object.getPrototypeOf(outerError) === NativeError.prototype &&
        \\outerError.message === "Invalid package config " + actualPackagePath + "." &&
        \\setterCode === "ERR_INVALID_PACKAGE_CONFIG" && nested[0] === "repaired" &&
        \\nested[1] === "after.js" && nested[2] === "none" &&
        \\nested[4] === '{"default":"./good.js"}' &&
        \\actualPackageRead(actualPackagePath)[0] === "repaired"
    );
    try std.testing.expect(f.repair_saw_empty_cache);
    try std.testing.expectEqual(@as(u32, 1), f.data.?.packageCache().entries.count());
}

test "native module package input native Error nonthrowing false code Set preserves repairability" {
    var disk = try Disk.init(); defer disk.deinit();
    try disk.write("{\"type\":false}");
    var f: Fixture = undefined; try f.init(&disk); defer f.deinit();
    try f.evaluate(
        \\Object.defineProperty(Error.prototype, "code", {
        \\  configurable: true, writable: false, value: "inherited"
        \\});
        \\try { actualPackageRead(actualPackagePath); }
        \\catch (error) { globalThis.reason = error; globalThis.inheritedCode = error.code; }
        \\delete Error.prototype.code;
    );
    try f.expect(
        \\reason instanceof Error && inheritedCode === "inherited" &&
        \\Object.getOwnPropertyDescriptor(reason, "code") === undefined &&
        \\reason.message === "Invalid package config " + actualPackagePath + "."
    );
    try std.testing.expectEqual(@as(u32, 0), f.data.?.packageCache().entries.count());
    try disk.write("{\"name\":\"fixed\"}");
    try f.expect("actualPackageRead(actualPackagePath)[0] === 'fixed'");
}

test "native module package input borrowed native Config remains stable across real cache growth" {
    var disk = try Disk.init(); defer disk.deinit();
    try disk.write("{\"name\":\"stable\"}");
    var f: Fixture = undefined; try f.init(&disk); defer f.deinit();
    const first_value = try f.read(disk.path); defer f.engine.freeValue(first_value);
    const first = f.data.?.packageCache().entries.get(disk.path).?.?;
    for (0..32) |index| {
        const name = try std.fmt.allocPrint(gpa, "growth-{d}.json", .{index});
        defer gpa.free(name);
        try disk.temporary.dir.writeFile(std.testing.io, .{ .sub_path = name, .data = "{}" });
        const path = try Disk.namedPath(&disk.temporary, name);
        defer gpa.free(path);
        const serialized = try f.read(path);
        f.engine.freeValue(serialized);
    }
    try std.testing.expect(first == f.data.?.packageCache().entries.get(disk.path).?.?);
    const config = first.views();
    const name: [*]const u8 = @ptrCast(config.name.data);
    try std.testing.expectEqualStrings("stable", name[0..config.name.length]);
    try std.testing.expectEqualStrings(disk.path, first.path);
    try std.testing.expectEqual(@as(u32, 33), f.data.?.packageCache().entries.count());
}

test "native module package input realm retirement clears its typed binding and releases native owners" {
    const owners = c.pi_js_native_memory_owners();
    var disk = try Disk.init(); defer disk.deinit();
    try disk.write("{\"name\":\"retired\",\"exports\":{\"x\":1}}");
    {
        var f: Fixture = undefined; try f.init(&disk); defer f.deinit();
        const value = try f.read(disk.path); defer f.engine.freeValue(value);
        const registry = try f.registry();
        try std.testing.expect(bindings.get(registry) == f.data.?);
        try std.testing.expect(registry.head == &f.data.?.base_entry);
        try std.testing.expect(registry.tail == &f.data.?.base_entry);
        try std.testing.expect(registry.fs_binding_data == null);
        try f.closeRealm();
        try std.testing.expect(bindings.get(registry) == null);
        try std.testing.expect(registry.head == null and registry.tail == null);
        try std.testing.expect(c.JS_GetOpaque(f.target, c.JS_GetClassID(f.target)) == null);
        // Already-serialized VM data remains valid after native Config cleanup.
        try f.expose("retiredResult", value);
        try f.expect("retiredResult[0] === 'retired' && retiredResult[4] === '{\"x\":1}'");
    }
    try std.testing.expectEqual(owners, c.pi_js_native_memory_owners());
}

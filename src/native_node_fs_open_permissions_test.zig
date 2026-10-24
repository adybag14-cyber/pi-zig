//! Real native CheckOpenPermissions controls. No syscall or public fs binding
//! is synthesized. Root owns compiler, metadata and runtime qualification.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const open = @import("extensions/native_node_fs_open_permissions.zig");
const functions = @import("extensions/native_node_function.zig");
const support = @import("native_node_native_debug_test_support.zig");
const c = a.c;
const n = support.c;
const gpa = std.testing.allocator;

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
        const args = [_]n.PiNodeEnvironmentPathSpan{support.span("native-fs-open-permissions")};
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
    fn inputs(self: *NativePolicy) open.NativeInputs {
        return .{ .permission = @ptrCast(self.permission.?),
            .environment = @ptrCast(&self.environment) };
    }
    fn enable(self: *NativePolicy) void {
        n.pi_node_permission_enable(self.permission.?);
    }
    fn allow(self: *NativePolicy, scope: c_int) void {
        const entries = [_]n.PiNodeEnvironmentPathSpan{support.span("*")};
        n.pi_node_permission_apply(self.permission.?, self.engine.native_memory_owner,
            &self.environment, &entries, entries.len, scope);
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
var active: ?*Fixture = null;
const Fixture = struct {
    engine: *a.v.em.Engine = undefined,
    engine_alive: bool = false,
    policy: NativePolicy = .{},
    policy_alive: bool = false,
    keys: open.PermissionKeys = undefined,
    keys_alive: bool = false,
    path: []const u8 = "native-open-permission-resource",

    fn init(self: *Fixture) !void {
        self.* = .{};
        errdefer self.deinit();
        self.engine = try a.v.em.Engine.init(gpa, .{});
        self.engine_alive = true;
        try self.policy.init(self.engine);
        self.policy_alive = true;
        active = self;
        const ignored = try a.expression(self.engine, bootstrap, .{self});
        self.engine.freeValue(ignored);
        try self.evaluate(
            \\globalThis.captureOpenDenial = (flags) => {
            \\  try { checkOpen(flags); return null; } catch (e) { return e; }
            \\};
        );
    }
    fn bootstrap(s: *a.Scope, self: *Fixture) !c.JSValue {
        self.keys = try open.PermissionKeys.create(s);
        self.keys.permission = a.duplicate(s.engine, self.keys.permission);
        self.keys.resource = a.duplicate(s.engine, self.keys.resource);
        self.keys_alive = true;
        const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
        const method = try s.own(try functions.createMethod(s.engine, "checkOpen", 1,
            checkCallback, &.{}));
        const allow_read = try s.own(try functions.createMethod(s.engine, "allowRead", 0,
            allowReadCallback, &.{}));
        const allow_write = try s.own(try functions.createMethod(s.engine, "allowWrite", 0,
            allowWriteCallback, &.{}));
        const replace_keys = try s.own(try functions.createMethod(s.engine, "replacePermissionKeys", 0,
            replaceKeysCallback, &.{}));
        try s.define(global, "checkOpen", method, c.JS_PROP_C_W_E);
        try s.define(global, "allowRead", allow_read, c.JS_PROP_C_W_E);
        try s.define(global, "allowWrite", allow_write, c.JS_PROP_C_W_E);
        try s.define(global, "replacePermissionKeys", replace_keys, c.JS_PROP_C_W_E);
        try s.define(global, "RDONLY", c.JS_NewInt32(s.engine.context, n.UV_FS_O_RDONLY), c.JS_PROP_C_W_E);
        try s.define(global, "WRONLY", c.JS_NewInt32(s.engine.context, n.UV_FS_O_WRONLY), c.JS_PROP_C_W_E);
        try s.define(global, "RDWR", c.JS_NewInt32(s.engine.context, n.UV_FS_O_RDWR), c.JS_PROP_C_W_E);
        return c.pi_js_undefined();
    }
    fn current(engine: *a.v.em.Engine) !*Fixture {
        const self = active orelse return error.ActualOpenPermissionFixtureRequired;
        if (self.engine != engine) return error.ActualOpenPermissionFixtureMismatch;
        return self;
    }
    fn checkCallback(engine: *a.v.em.Engine, _: c.JSValue,
        args: []const c.JSValue, _: []const c.JSValue) !c.JSValue
    {
        return a.expression(engine, checkBody, .{ try current(engine), args });
    }
    fn checkBody(s: *a.Scope, self: *Fixture, args: []const c.JSValue) !c.JSValue {
        // Fixture-only integer input. The production helper consumes the real
        // original callback's already-validated native Int32 flags.
        var flags: c_int = 0;
        try s.pending();
        const status = c.JS_ToInt32(s.engine.context, &flags, a.arg(args, 0));
        try s.pending();
        if (status < 0) return error.ActualOpenFixtureIntegerRequired;
        try open.checkOpenPermissions(s, self.policy.inputs(), self.keys, self.path, flags);
        return c.pi_js_undefined();
    }
    fn allowReadCallback(engine: *a.v.em.Engine, _: c.JSValue,
        _: []const c.JSValue, _: []const c.JSValue) !c.JSValue
    {
        (try current(engine)).policy.allow(n.PI_NODE_PERMISSION_FS_READ);
        return c.pi_js_undefined();
    }
    fn allowWriteCallback(engine: *a.v.em.Engine, _: c.JSValue,
        _: []const c.JSValue, _: []const c.JSValue) !c.JSValue
    {
        (try current(engine)).policy.allow(n.PI_NODE_PERMISSION_FS_WRITE);
        return c.pi_js_undefined();
    }
    fn replaceKeysCallback(engine: *a.v.em.Engine, _: c.JSValue,
        _: []const c.JSValue, _: []const c.JSValue) !c.JSValue
    {
        return a.expression(engine, replaceKeysBody, .{try current(engine)});
    }
    fn replaceKeysBody(s: *a.Scope, self: *Fixture) !c.JSValue {
        var next = try open.PermissionKeys.create(s);
        next.permission = a.duplicate(s.engine, next.permission);
        next.resource = a.duplicate(s.engine, next.resource);
        const previous = self.keys;
        self.keys = next;
        s.engine.freeValue(previous.permission);
        s.engine.freeValue(previous.resource);
        c.JS_RunGC(s.engine.runtime);
        return c.pi_js_undefined();
    }
    fn invoke(s: *a.Scope, inputs: open.NativeInputs, keys: open.PermissionKeys,
        path: []const u8, flags: c_int) !c.JSValue
    {
        try open.checkOpenPermissions(s, inputs, keys, path, flags);
        return c.pi_js_undefined();
    }
    fn permit(self: *Fixture, flags: c_int) !void {
        const value = try a.expression(self.engine, invoke,
            .{self.policy.inputs(), self.keys, self.path, flags});
        defer self.engine.freeValue(value);
        try std.testing.expect(c.JS_IsUndefined(value));
    }
    fn flag(self: *Fixture, value: c_int) !void {
        const ignored = try a.expression(self.engine, struct {
            fn run(s: *a.Scope, input: c_int) !c.JSValue {
                const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
                try s.define(global, "flagsUnderTest", c.JS_NewInt32(s.engine.context, input), c.JS_PROP_C_W_E);
                return c.pi_js_undefined();
            }
        }.run, .{value});
        self.engine.freeValue(ignored);
    }
    fn evaluate(self: *Fixture, source: []const u8) !void {
        const value = try self.engine.eval(source, "native-fs-open-permissions.js", c.JS_EVAL_TYPE_GLOBAL);
        self.engine.freeValue(value);
    }
    fn expect(self: *Fixture, source: []const u8) !void {
        const value = try self.engine.eval(source, "native-fs-open-permissions.js", c.JS_EVAL_TYPE_GLOBAL);
        defer self.engine.freeValue(value);
        try std.testing.expect(c.JS_ToBool(self.engine.context, value) == 1);
    }
    fn deinit(self: *Fixture) void {
        if (self.keys_alive) {
            self.keys_alive = false;
            self.engine.freeValue(self.keys.permission);
            self.engine.freeValue(self.keys.resource);
        }
        if (self.policy_alive) {
            self.policy.deinit();
            self.policy_alive = false;
        }
        if (self.engine_alive) {
            self.engine.deinit();
            self.engine_alive = false;
        }
        if (active == self) active = null;
    }
};

test "native fs open permissions disabled native policy accepts access and side effect modes without errors" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate(
        \\globalThis.errorCalls = 0;
        \\Object.defineProperty(Error.prototype, "code", { configurable: true,
        \\  set() { errorCalls++; throw new TypeError("denial must not be constructed"); } });
    );
    for ([_]c_int{ n.UV_FS_O_RDONLY, n.UV_FS_O_WRONLY, n.UV_FS_O_RDWR,
        n.UV_FS_O_RDONLY | n.UV_FS_O_CREAT | n.UV_FS_O_TRUNC,
        n.UV_FS_O_RDONLY | n.UV_FS_O_APPEND | n.UV_FS_O_TEMPORARY }) |flags|
        try f.permit(flags);
    try f.expect("errorCalls === 0");
}
test "native fs open permissions read only needs the actual read grant" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.policy.enable();
    f.policy.allow(n.PI_NODE_PERMISSION_FS_READ);
    try f.permit(n.UV_FS_O_RDONLY);
    try f.expect("captureOpenDenial(WRONLY).permission === 'FileSystemWrite'");
}
test "native fs open permissions write only skips the denied read policy" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.policy.enable();
    f.policy.allow(n.PI_NODE_PERMISSION_FS_WRITE);
    try f.permit(n.UV_FS_O_WRONLY);
    try f.expect("captureOpenDenial(RDONLY).permission === 'FileSystemRead'");
}
test "native fs open permissions read write checks read first then requires write" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.policy.enable();
    try f.expect("captureOpenDenial(RDWR).permission === 'FileSystemRead'");
    f.policy.allow(n.PI_NODE_PERMISSION_FS_READ);
    try f.expect("captureOpenDenial(RDWR).permission === 'FileSystemWrite'");
    f.policy.allow(n.PI_NODE_PERMISSION_FS_WRITE);
    try f.permit(n.UV_FS_O_RDWR);
}
test "native fs open permissions combined access mode bits require both original comparisons" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.policy.enable();
    f.policy.allow(n.PI_NODE_PERMISSION_FS_WRITE);
    try f.flag(n.UV_FS_O_WRONLY | n.UV_FS_O_RDWR);
    try f.expect("captureOpenDenial(flagsUnderTest).permission === 'FileSystemRead'");
    f.policy.allow(n.PI_NODE_PERMISSION_FS_READ);
    try f.permit(n.UV_FS_O_WRONLY | n.UV_FS_O_RDWR);
}
test "native fs open permissions readonly write side effects require real write permission" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.policy.enable();
    f.policy.allow(n.PI_NODE_PERMISSION_FS_READ);
    for ([_]c_int{ n.UV_FS_O_APPEND, n.UV_FS_O_CREAT, n.UV_FS_O_TRUNC,
        n.UV_FS_O_TEMPORARY }) |side_effect| {
        if (side_effect == 0) continue; // Original platform has no such flag.
        try f.flag(n.UV_FS_O_RDONLY | side_effect);
        try f.expect("captureOpenDenial(flagsUnderTest).permission === 'FileSystemWrite'");
    }
    f.policy.allow(n.PI_NODE_PERMISSION_FS_WRITE);
    try f.permit(n.UV_FS_O_RDONLY | n.UV_FS_O_APPEND | n.UV_FS_O_CREAT |
        n.UV_FS_O_TRUNC | n.UV_FS_O_TEMPORARY);
}
test "native fs open permissions side effects do not skip the prior read denial" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.policy.enable();
    f.policy.allow(n.PI_NODE_PERMISSION_FS_WRITE);
    try f.flag(n.UV_FS_O_RDONLY | n.UV_FS_O_CREAT | n.UV_FS_O_TRUNC);
    try f.expect("captureOpenDenial(flagsUnderTest).permission === 'FileSystemRead'");
}
test "native fs open permissions unrelated flag bits do not invent a write requirement" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.policy.enable();
    f.policy.allow(n.PI_NODE_PERMISSION_FS_READ);
    const unrelated: c_int = n.UV_FS_O_EXCL | n.UV_FS_O_NONBLOCK;
    try f.permit(n.UV_FS_O_RDONLY | unrelated);
}
test "native fs open permissions observes live native enable and later scope grants" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.permit(n.UV_FS_O_RDWR);
    f.policy.enable();
    try f.expect("captureOpenDenial(RDWR).permission === 'FileSystemRead'");
    f.policy.allow(n.PI_NODE_PERMISSION_FS_READ);
    try f.expect("captureOpenDenial(RDWR).permission === 'FileSystemWrite'");
    f.policy.allow(n.PI_NODE_PERMISSION_FS_WRITE);
    try f.permit(n.UV_FS_O_RDWR);
}
test "native fs open permissions write denial uses fresh intrinsic Error and write flag suggestion" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.policy.enable();
    try f.evaluate(
        \\globalThis.NativeError = Error;
        \\globalThis.Error = function() { throw "public Error must not be called"; };
        \\globalThis.first = captureOpenDenial(WRONLY);
        \\globalThis.second = captureOpenDenial(WRONLY);
    );
    try f.expect(
        \\first !== second && first instanceof NativeError && second instanceof NativeError &&
        \\first.code === "ERR_ACCESS_DENIED" && first.permission === "FileSystemWrite" &&
        \\first.resource === "native-open-permission-resource" &&
        \\first.message === "Access to this API has been restricted. Use --allow-fs-write to manage permissions." &&
        \\Object.getOwnPropertyDescriptor(first, "message").enumerable === false &&
        \\Object.getOwnPropertyDescriptor(first, "code").enumerable === true
    );
}
test "native fs open permissions code setter reentry repairs actual policy and retains original denial keys" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.policy.enable();
    f.policy.allow(n.PI_NODE_PERMISSION_FS_READ);
    try f.evaluate(
        \\globalThis.order = []; globalThis.nested = "not called";
        \\Object.defineProperty(Error.prototype, "code", { configurable: true, set(value) {
        \\  order.push("code:" + value); replacePermissionKeys(); allowWrite();
        \\  nested = checkOpen(RDWR);
        \\  Object.defineProperty(this, "code", { value, writable: true, enumerable: true, configurable: true });
        \\}});
        \\Object.defineProperty(Error.prototype, "permission", { configurable: true, set(value) {
        \\  order.push("permission:" + value);
        \\  Object.defineProperty(this, "permission", { value, writable: true, enumerable: true, configurable: true });
        \\}});
        \\Object.defineProperty(Error.prototype, "resource", { configurable: true, set(value) {
        \\  order.push("resource:" + value);
        \\  Object.defineProperty(this, "resource", { value, writable: true, enumerable: true, configurable: true });
        \\}});
        \\globalThis.outer = captureOpenDenial(RDWR);
    );
    try f.expect(
        \\nested === undefined && outer.permission === "FileSystemWrite" &&
        \\order.join("|") === "code:ERR_ACCESS_DENIED|permission:FileSystemWrite|resource:native-open-permission-resource" &&
        \\checkOpen(RDWR) === undefined
    );
}
test "native fs open permissions thrown permission setter supersedes denial and skips resource" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.policy.enable();
    try f.evaluate(
        \\globalThis.marker = {}; globalThis.resourceCalls = 0;
        \\Object.defineProperty(Error.prototype, "permission", { configurable: true, set(value) {
        \\  if (value !== "FileSystemWrite") throw "wrong scope"; throw marker;
        \\}});
        \\Object.defineProperty(Error.prototype, "resource", { configurable: true, set() { resourceCalls++; }});
        \\globalThis.result = captureOpenDenial(WRONLY);
    );
    try f.expect("result === marker && resourceCalls === 0");
}
test "native fs open permissions thrown resource setter supersedes the completed permission set" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.policy.enable();
    try f.evaluate(
        \\globalThis.marker = {}; globalThis.observedPermission = null;
        \\Object.defineProperty(Error.prototype, "resource", { configurable: true, set(value) {
        \\  observedPermission = this.permission;
        \\  if (value !== "native-open-permission-resource") throw "wrong resource";
        \\  throw marker;
        \\}});
        \\globalThis.result = captureOpenDenial(WRONLY);
    );
    try f.expect("result === marker && observedPermission === 'FileSystemWrite'");
}
test "native fs open permissions nonthrowing false code permission resource Sets preserve denial" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.policy.enable();
    try f.evaluate(
        \\for (const name of ["code", "permission", "resource"])
        \\  Object.defineProperty(Error.prototype, name, { value: "blocked-" + name, writable: false, configurable: true });
        \\globalThis.result = captureOpenDenial(WRONLY);
    );
    try f.expect(
        \\result instanceof Error && result.code === "blocked-code" &&
        \\result.permission === "blocked-permission" && result.resource === "blocked-resource" &&
        \\!Object.hasOwn(result, "code") && !Object.hasOwn(result, "permission") && !Object.hasOwn(result, "resource") &&
        \\result.message === "Access to this API has been restricted. Use --allow-fs-write to manage permissions."
    );
}
test "native fs open permissions error resource retains the complete BufferValue span including NUL" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.policy.enable();
    f.path = "native-prefix\x00native-suffix";
    try f.expect(
        \\(() => { const e = captureOpenDenial(WRONLY); return e.resource === "native-prefix\0native-suffix" &&
        \\e.permission === "FileSystemWrite" && e.resource.length === 27; })()
    );
    f.path = "";
    try f.expect("captureOpenDenial(WRONLY).resource === ''");
}
test "native fs open permissions rejects foreign native context and primitive key owners before policy" {
    var first: Fixture = undefined; try first.init(); defer first.deinit();
    var second: Fixture = undefined; try second.init(); defer second.deinit();
    try std.testing.expectError(error.ActualOpenPermissionEnvironmentRequired,
        a.expression(first.engine, Fixture.invoke,
            .{second.policy.inputs(), first.keys, first.path, @as(c_int, n.UV_FS_O_RDONLY)}));
    try std.testing.expectError(error.ActualNativePermissionKeysRequired,
        a.expression(first.engine, Fixture.invoke,
            .{first.policy.inputs(), second.keys, first.path, @as(c_int, n.UV_FS_O_RDONLY)}));
}

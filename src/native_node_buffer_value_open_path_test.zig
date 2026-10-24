//! Actual BufferValue and pre-request OpenFileHandle source controls.
//! Real native Permission/EnvironmentPath/Map owners share Engine memory.
//! These controls install no physical request or replacement fs namespace.
const std = @import("std");
const builtin = @import("builtin");
const a = @import("extensions/native_node_argument_values.zig");
const c = a.c;
const buffers = @import("extensions/native_node_buffer_value.zig");
const path_owner = @import("extensions/native_node_fs_open_path.zig");
const temporary = @import("extensions/native_node_maybe_stack_buffer.zig");
const open = @import("extensions/native_node_fs_open_permissions.zig");
const callbacks = @import("extensions/native_node_callback_scope.zig");
const providers = @import("extensions/native_node_async_providers.zig");
const functions = @import("extensions/native_node_function.zig");
const support = @import("native_node_native_debug_test_support.zig");
const n = support.c;
const gpa = std.testing.allocator;

fn unselected(_: *callbacks.Environment) anyerror!void {
    return error.UnselectedBufferValueEnvironmentOperation;
}
fn unselectedCheck(_: *callbacks.Environment, _: callbacks.Check) anyerror {
    return error.UnselectedBufferValueEnvironmentCheck;
}
fn unselectedCorruption(_: *callbacks.Environment, _: f64) anyerror {
    return error.UnselectedBufferValueStackCorruption;
}
const operations: callbacks.Operations = .{
    .on_hook_exception = unselected,
    .native_check_failure = unselectedCheck,
    .fail_corrupted_async_stack = unselectedCorruption,
    .perform_checkpoint = unselected,
    .schedule_destroy_immediate = unselected,
    .request_destroy_interrupt = unselected,
};

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
    fn setEnv(self: *NativePolicy, key: []const u8, value: []const u8) void {
        n.pi_node_environment_map_lock(self.map.?);
        defer n.pi_node_environment_map_unlock(self.map.?);
        n.pi_node_environment_map_set_locked(self.map.?, key.ptr, key.len, value.ptr, value.len);
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
const Fixture = struct {
    engine: *a.v.em.Engine = undefined,
    engine_alive: bool = false,
    process_environment: std.process.Environ.Map = undefined,
    process_environment_alive: bool = false,
    environment: ?*callbacks.Environment = null,
    policy: NativePolicy = .{},
    policy_alive: bool = false,
    keys: open.PermissionKeys = undefined,
    keys_alive: bool = false,
    active_arguments: ?*path_owner.Arguments = null,
    prepared_flags: c_int = 0,
    prepared_mode: c_int = 0,

    fn init(self: *Fixture) !void {
        self.* = .{};
        self.process_environment = .init(gpa);
        self.process_environment_alive = true;
        errdefer self.deinit();
        self.engine = try a.v.em.Engine.init(gpa, .{});
        self.engine_alive = true;
        self.engine.host_control_context = self;
        try @import("extensions/native_process.zig").install(self.engine,
            std.testing.io, &self.process_environment, &.{"native-buffer-value-open-path"});
        try self.policy.init(self.engine);
        self.policy_alive = true;
        const ignored = try a.expression(self.engine, bootstrap, .{self});
        self.engine.freeValue(ignored);
    }
    fn bootstrap(s: *a.Scope, self: *Fixture) !c.JSValue {
        const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
        const process = try s.get(global, "process");
        const generation = try s.beforeAllocation();
        const symbol = try s.checkedAllocation(c.JS_NewSymbol(
            s.engine.context, "node:resource_symbol", false), generation);
        self.environment = try callbacks.Environment.create(s.engine, .{
            .provider_names = providers.names(false), .resource_symbol = symbol,
            .process_object = process, .async_context_frame = true,
            .operations = operations,
        });
        self.env().markBootstrapComplete();
        self.keys = try open.PermissionKeys.create(s);
        self.keys.permission = a.duplicate(s.engine, self.keys.permission);
        self.keys.resource = a.duplicate(s.engine, self.keys.resource);
        self.keys_alive = true;
        const prepare = try s.own(try functions.createMethod(s.engine,
            "prepareNativeOpenPath", 3, prepareCallback, &.{}));
        const inspect = try s.own(try functions.createMethod(s.engine,
            "inspectNativeOpenPath", 0, inspectCallback, &.{}));
        const collect = try s.own(try functions.createMethod(s.engine,
            "collectNativeOpenPath", 0, gcCallback, &.{}));
        const permit_read = try s.own(try functions.createMethod(s.engine,
            "allowNativePathRead", 0, allowReadCallback, &.{}));
        try s.define(global, "prepareNativeOpenPath", prepare, c.JS_PROP_C_W_E);
        try s.define(global, "inspectNativeOpenPath", inspect, c.JS_PROP_C_W_E);
        try s.define(global, "collectNativeOpenPath", collect, c.JS_PROP_C_W_E);
        try s.define(global, "allowNativePathRead", permit_read, c.JS_PROP_C_W_E);
        try s.define(global, "nativePathReadOnly",
            c.JS_NewInt32(s.engine.context, n.UV_FS_O_RDONLY), c.JS_PROP_C_W_E);
        return c.pi_js_undefined();
    }
    fn env(self: *Fixture) *callbacks.Environment { return self.environment.?; }
    fn fromEngine(engine: *a.v.em.Engine) *Fixture {
        return @ptrCast(@alignCast(engine.host_control_context.?));
    }
    fn prepareCallback(engine: *a.v.em.Engine, _: c.JSValue,
        args: []const c.JSValue, _: []const c.JSValue) !c.JSValue
    {
        return a.expression(engine, prepareBody, .{ fromEngine(engine), args });
    }
    fn prepareBody(s: *a.Scope, self: *Fixture, args: []const c.JSValue) !c.JSValue {
        var prepared: path_owner.Arguments = .{};
        const previous = self.active_arguments;
        self.active_arguments = &prepared;
        defer self.active_arguments = previous;
        try prepared.init(s, self.env(), self.policy.inputs(), self.keys, args);
        defer prepared.deinit();
        self.prepared_flags = prepared.flags;
        self.prepared_mode = prepared.mode;
        return a.duplicate(s.engine, try s.text(prepared.path.bytes().?));
    }
    fn inspectCallback(engine: *a.v.em.Engine, _: c.JSValue,
        _: []const c.JSValue, _: []const c.JSValue) !c.JSValue
    {
        return a.expression(engine, struct {
            fn body(s: *a.Scope, self: *Fixture) !c.JSValue {
                const prepared = self.active_arguments orelse
                    return error.ActualOpenPathArgumentsRequired;
                return a.duplicate(s.engine, try s.text(prepared.path.bytes().?));
            }
        }.body, .{fromEngine(engine)});
    }
    fn gcCallback(engine: *a.v.em.Engine, _: c.JSValue,
        _: []const c.JSValue, _: []const c.JSValue) !c.JSValue
    {
        c.JS_RunGC(engine.runtime);
        return c.pi_js_undefined();
    }
    fn allowReadCallback(engine: *a.v.em.Engine, _: c.JSValue,
        _: []const c.JSValue, _: []const c.JSValue) !c.JSValue
    {
        fromEngine(engine).policy.allow(n.PI_NODE_PERMISSION_FS_READ);
        return c.pi_js_undefined();
    }
    fn evalValue(self: *Fixture, source: []const u8) !c.JSValue {
        return self.engine.eval(source, "native-buffer-value-open-path.js", c.JS_EVAL_TYPE_GLOBAL);
    }
    fn evaluate(self: *Fixture, source: []const u8) !void {
        const value = try self.evalValue(source);
        self.engine.freeValue(value);
    }
    fn expect(self: *Fixture, source: []const u8) !void {
        const value = try self.evalValue(source);
        defer self.engine.freeValue(value);
        try std.testing.expect(c.JS_ToBool(self.engine.context, value) == 1);
    }
    fn convert(self: *Fixture, target: *buffers.BufferValue, input: ?c.JSValue) !void {
        const ignored = try a.expression(self.engine, struct {
            fn body(s: *a.Scope, f: *Fixture, result: *buffers.BufferValue,
                value: ?c.JSValue) !c.JSValue
            {
                try result.init(s, f.env(), value);
                return c.pi_js_undefined();
            }
        }.body, .{ self, target, input });
        self.engine.freeValue(ignored);
    }
    fn sourceBuffer(self: *Fixture, target: *buffers.BufferValue, source: []const u8) !void {
        const value = try self.evalValue(source);
        defer self.engine.freeValue(value);
        try self.convert(target, value);
    }
    fn namespace(self: *Fixture, target: *buffers.BufferValue) !void {
        const ignored = try a.expression(self.engine, struct {
            fn body(s: *a.Scope, f: *Fixture, result: *buffers.BufferValue) !c.JSValue {
                try path_owner.toNamespacedPath(s, result, @ptrCast(&f.policy.environment));
                return c.pi_js_undefined();
            }
        }.body, .{ self, target });
        self.engine.freeValue(ignored);
    }
    fn deinit(self: *Fixture) void {
        if (self.keys_alive) {
            self.keys_alive = false;
            self.engine.freeValue(self.keys.permission);
            self.engine.freeValue(self.keys.resource);
        }
        if (self.environment) |environment| {
            environment.cleanupRealmAfterIoJoin() catch @panic("BufferValue realm cleanup failed");
            environment.disarm() catch @panic("BufferValue Environment disarm failed");
            self.environment = null;
            environment.release();
        }
        if (self.policy_alive) { self.policy.deinit(); self.policy_alive = false; }
        if (self.engine_alive) {
            self.engine.host_control_context = null;
            self.engine.deinit(); self.engine_alive = false;
        }
        if (self.process_environment_alive) {
            self.process_environment.deinit();
            self.process_environment_alive = false;
        }
    }
};

fn expectBytes(value: *buffers.BufferValue, expected: []const u8) !void {
    const actual = value.bytes() orelse return error.ExpectedValidNativeBufferValue;
    try std.testing.expectEqualSlices(u8, expected, actual);
    try std.testing.expectEqual(@as(u8, 0), actual.ptr[actual.len]);
}

test "native BufferValue invalid inputs do not coerce boxed values or enter proxy traps" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate("globalThis.bufferValueTraps=0;");
    inline for (.{
        "undefined", "null", "17", "true", "1n", "Symbol('path')",
        "new String('path')", "new ArrayBuffer(8)", "new SharedArrayBuffer(8)",
        "({toString(){bufferValueTraps++;throw 1;},valueOf(){bufferValueTraps++;throw 2;}})",
        "new Proxy(new Uint8Array(4),{get(){bufferValueTraps++;throw 3;}})",
        "(()=>{const r=Proxy.revocable(new DataView(new ArrayBuffer(4)),{});r.revoke();return r.proxy;})()",
    }) |source| {
        var result: buffers.BufferValue = .{};
        try f.sourceBuffer(&result, source); defer result.deinit();
        try std.testing.expect(result.bytes() == null);
        try std.testing.expectEqual(@as(usize, 0), result.capacity());
        try std.testing.expect(!result.isAllocated());
    }
    try f.expect("bufferValueTraps===0");
}

test "native BufferValue distinguishes an absent Local from valid empty string and views" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var absent: buffers.BufferValue = .{};
    try f.convert(&absent, null); defer absent.deinit();
    try std.testing.expect(absent.bytes() == null);
    inline for (.{ "''", "new Uint8Array(0)", "new DataView(new ArrayBuffer(0))" }) |source| {
        var result: buffers.BufferValue = .{};
        try f.sourceBuffer(&result, source); defer result.deinit();
        try expectBytes(&result, "");
        try std.testing.expectEqual(@as(usize, 1024), result.capacity());
        try std.testing.expect(!result.isAllocated());
    }
}

test "native BufferValue Latin1 UTF8 preserves embedded NUL and high bytes" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var result: buffers.BufferValue = .{};
    try f.sourceBuffer(&result, "'A\\0\\x80\\xff'"); defer result.deinit();
    try expectBytes(&result, &.{ 'A', 0, 0xc2, 0x80, 0xc3, 0xbf });
}

test "native BufferValue wide UTF8 replaces isolated surrogates and preserves a pair" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var result: buffers.BufferValue = .{};
    try f.sourceBuffer(&result, "'\\ud800X\\udc00\\ud83d\\ude42'"); defer result.deinit();
    try expectBytes(&result, &.{ 0xef, 0xbf, 0xbd, 'X', 0xef, 0xbf, 0xbd,
        0xf0, 0x9f, 0x99, 0x82 });
}

test "native BufferValue owns the flattened rope bytes beyond the JS Scope and GC" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var result: buffers.BufferValue = .{};
    try f.sourceBuffer(&result, "'a'.repeat(800)+'\\u0100'+'b'.repeat(400)");
    defer result.deinit();
    c.JS_RunGC(f.engine.runtime);
    const actual = result.bytes().?;
    try std.testing.expectEqual(@as(usize, 1202), actual.len);
    for (actual[0..800]) |byte| try std.testing.expectEqual(@as(u8, 'a'), byte);
    try std.testing.expectEqualSlices(u8, &.{ 0xc4, 0x80 }, actual[800..802]);
    for (actual[802..]) |byte| try std.testing.expectEqual(@as(u8, 'b'), byte);
    try std.testing.expect(result.isAllocated());
    try std.testing.expectEqual(@as(u8, 0), actual.ptr[actual.len]);
}

test "native BufferValue Latin1 allocation uses exact UTF8 only past original stack threshold" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    inline for (.{
        .{ "'\\xff'.repeat(511)", 1022, 1024, false },
        .{ "'\\xff'.repeat(512)", 1024, 1025, true },
        .{ "'a'.repeat(1023)", 1023, 1024, false },
        .{ "'a'.repeat(1024)", 1024, 1025, true },
    }) |case| {
        var result: buffers.BufferValue = .{};
        try f.sourceBuffer(&result, case[0]); defer result.deinit();
        try std.testing.expectEqual(@as(usize, case[1]), result.bytes().?.len);
        try std.testing.expectEqual(@as(usize, case[2]), result.capacity());
        try std.testing.expectEqual(case[3], result.isAllocated());
        try std.testing.expectEqual(@as(u8, 0), result.bytes().?.ptr[case[1]]);
    }
}

test "native BufferValue wide storage reserves three bytes per UTF16 unit before writing" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    inline for (.{
        .{ "'\\u0100'.repeat(341)", 682, 1024, false },
        .{ "'\\u0100'.repeat(342)", 684, 1027, true },
    }) |case| {
        var result: buffers.BufferValue = .{};
        try f.sourceBuffer(&result, case[0]); defer result.deinit();
        try std.testing.expectEqual(@as(usize, case[1]), result.bytes().?.len);
        try std.testing.expectEqual(@as(usize, case[2]), result.capacity());
        try std.testing.expectEqual(case[3], result.isAllocated());
        try std.testing.expectEqual(@as(u8, 0), result.bytes().?.ptr[case[1]]);
    }
}

test "native BufferValue MaybeStackBuffer growth preserves logical prefix without shrinking storage" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var storage: temporary.Buffer(u8, 8) = undefined;
    try storage.init(f.env(), 4); defer storage.deinit();
    @memcpy(storage.data(), "copy");
    try storage.allocateSufficientStorage(12);
    try std.testing.expectEqualSlices(u8, "copy", storage.capacityData()[0..4]);
    const first_heap = storage.capacityData().ptr;
    try storage.allocateSufficientStorage(2);
    try std.testing.expectEqual(@as(usize, 2), storage.length);
    try std.testing.expectEqual(@as(usize, 12), storage.capacity());
    try std.testing.expect(first_heap == storage.capacityData().ptr);
    try storage.allocateSufficientStorage(24);
    try std.testing.expectEqualSlices(u8, "co", storage.capacityData()[0..2]);
    try std.testing.expectEqual(@as(usize, 24), storage.capacity());
}

test "native BufferValue copies a view offset before backing mutation detach and GC" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate(
        \\globalThis.originalBytes=new Uint8Array([91,92,1,2,3,4,93]);
        \\globalThis.originalView=new Uint8Array(originalBytes.buffer,2,4);
    );
    var result: buffers.BufferValue = .{};
    try f.sourceBuffer(&result, "originalView"); defer result.deinit();
    try f.evaluate("originalBytes.fill(9);");
    const backing = try f.evalValue("originalBytes.buffer");
    defer f.engine.freeValue(backing);
    c.JS_DetachArrayBuffer(f.engine.context, backing);
    c.JS_RunGC(f.engine.runtime);
    try expectBytes(&result, &.{ 1, 2, 3, 4 });
}

test "native BufferValue accepts all actual typed array kinds and DataView as raw byte spans" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate(
        \\globalThis.kindBacking=new ArrayBuffer(16);
        \\globalThis.kindBytes=new Uint8Array(kindBacking);
        \\for(let i=0;i<16;i++)kindBytes[i]=i;
    );
    inline for (.{
        "new Uint8ClampedArray(kindBacking,4,4)", "new Int8Array(kindBacking,4,4)",
        "new Uint8Array(kindBacking,4,4)", "new Int16Array(kindBacking,4,2)",
        "new Uint16Array(kindBacking,4,2)", "new Int32Array(kindBacking,4,1)",
        "new Uint32Array(kindBacking,4,1)", "new Float16Array(kindBacking,4,2)",
        "new Float32Array(kindBacking,4,1)", "new DataView(kindBacking,4,4)",
    }) |source| {
        var result: buffers.BufferValue = .{};
        try f.sourceBuffer(&result, source); defer result.deinit();
        try expectBytes(&result, &.{ 4, 5, 6, 7 });
    }
    inline for (.{
        "new BigInt64Array(kindBacking,8,1)", "new BigUint64Array(kindBacking,8,1)",
        "new Float64Array(kindBacking,8,1)",
    }) |source| {
        var result: buffers.BufferValue = .{};
        try f.sourceBuffer(&result, source); defer result.deinit();
        try expectBytes(&result, &.{ 8, 9, 10, 11, 12, 13, 14, 15 });
    }
}

test "native BufferValue intrinsic view reads ignore hostile public view properties" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var result: buffers.BufferValue = .{};
    try f.sourceBuffer(&result,
        \\(()=>{const v=new Uint8Array([7,0,9]);
        \\for(const key of ["buffer","byteLength","byteOffset","constructor"])
        \\Object.defineProperty(v,key,{get(){throw new Error("public accessor entered");}});
        \\return v;})()
    );
    defer result.deinit();
    try expectBytes(&result, &.{ 7, 0, 9 });
}

test "native BufferValue detached actual typed array and DataView copy valid empty spans" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate(
        \\globalThis.detachedBacking=new ArrayBuffer(8);
        \\globalThis.detachedTyped=new Uint16Array(detachedBacking,2,2);
        \\globalThis.detachedView=new DataView(detachedBacking,2,4);
    );
    const backing = try f.evalValue("detachedBacking"); defer f.engine.freeValue(backing);
    c.JS_DetachArrayBuffer(f.engine.context, backing);
    inline for (.{ "detachedTyped", "detachedView" }) |source| {
        var result: buffers.BufferValue = .{};
        try f.sourceBuffer(&result, source); defer result.deinit();
        try expectBytes(&result, "");
    }
}

test "native BufferValue out of bounds fixed resizable views are valid empty without JS errors" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate(
        \\globalThis.resizedBacking=new ArrayBuffer(16,{maxByteLength:32});
        \\globalThis.resizedTyped=new Uint16Array(resizedBacking,8,2);
        \\globalThis.resizedView=new DataView(resizedBacking,8,4);
        \\resizedBacking.resize(4);
    );
    inline for (.{ "resizedTyped", "resizedView" }) |source| {
        var result: buffers.BufferValue = .{};
        try f.sourceBuffer(&result, source); defer result.deinit();
        try expectBytes(&result, "");
    }
}

test "native BufferValue tracking view CopyContents keeps original zero stored length semantics" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    inline for (.{
        "new Uint8Array(new ArrayBuffer(12,{maxByteLength:32}),2)",
        "new DataView(new ArrayBuffer(12,{maxByteLength:32}),2)",
        "new Uint8Array(new SharedArrayBuffer(12,{maxByteLength:32}),2)",
        "new DataView(new SharedArrayBuffer(12,{maxByteLength:32}),2)",
    }) |source| {
        const view = try f.evalValue(source); defer f.engine.freeValue(view);
        try std.testing.expectEqual(@as(usize, 10), c.JS_PiArrayBufferViewByteLength(view));
        var destination: [16]u8 = @splat(0xcc);
        try std.testing.expectEqual(@as(usize, 0),
            c.JS_PiArrayBufferViewCopyContents(view, &destination, 10));
        for (destination) |byte| try std.testing.expectEqual(@as(u8, 0xcc), byte);
        var result: buffers.BufferValue = .{};
        try f.convert(&result, view); defer result.deinit();
        const actual = result.bytes().?;
        try std.testing.expectEqual(@as(usize, 10), actual.len);
        // Only the default constructor's first byte and appended terminator
        // are initialized. Never observe the original uninitialized suffix.
        try std.testing.expectEqual(@as(u8, 0), actual.ptr[0]);
        try std.testing.expectEqual(@as(u8, 0), actual.ptr[10]);
    }
}

test "native BufferValue CopyContents clips capacity and preserves pending exception without allocation" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const view = try f.evalValue("new Uint8Array([10,11,12,13])");
    defer f.engine.freeValue(view);
    const reason = try f.evalValue("({copyContentsReason:true})");
    defer f.engine.freeValue(reason);
    const before = c.pi_js_native_memory_used(f.engine.native_memory_owner);
    _ = c.JS_Throw(f.engine.context, a.duplicate(f.engine, reason));
    var destination: [6]u8 = @splat(0xcc);
    try std.testing.expectEqual(@as(usize, 2),
        c.JS_PiArrayBufferViewCopyContents(view, &destination, 2));
    try std.testing.expectEqualSlices(u8, &.{ 10, 11, 0xcc, 0xcc, 0xcc, 0xcc }, &destination);
    try std.testing.expectEqual(before, c.pi_js_native_memory_used(f.engine.native_memory_owner));
    try std.testing.expect(c.JS_HasException(f.engine.context));
    const caught = c.JS_GetException(f.engine.context); defer f.engine.freeValue(caught);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, caught, reason));
}

const External = struct {
    calls: usize = 0,
    fn retire(_: ?*c.JSRuntime, raw_owner: ?*anyopaque,
        pointer: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque
    {
        const self: *External = @ptrCast(@alignCast(raw_owner.?));
        if (pointer == null or size != 0) @panic("Unexpected external storage resize");
        self.calls += 1;
        return null;
    }
};

test "native BufferValue byte copy adds no external backing lease and survives its detach release" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var external: External = .{};
    var native_bytes = [_]u8{ 91, 92, 1, 2, 3, 4, 93, 94 };
    var backing: c.JSValue = undefined;
    var view: c.JSValue = undefined;
    const ignored = try a.expression(f.engine, struct {
        fn body(s: *a.Scope, bytes: []u8, owner: *External,
            backing_out: *c.JSValue, view_out: *c.JSValue) !c.JSValue
        {
            const buffer_generation = try s.beforeAllocation();
            const buffer = try s.checkedAllocation(c.JS_NewArrayBuffer(
                s.engine.context, bytes.ptr, bytes.len, 0, External.retire, owner, false),
                buffer_generation);
            const arguments = [_]c.JSValue{ buffer, c.JS_NewInt32(s.engine.context, 2),
                c.JS_NewInt32(s.engine.context, 4) };
            const view_generation = try s.beforeAllocation();
            const typed = try s.checkedAllocation(c.JS_NewTypedArray(
                s.engine.context, arguments.len, @constCast(&arguments), c.JS_TYPED_ARRAY_UINT8),
                view_generation);
            backing_out.* = a.duplicate(s.engine, buffer);
            view_out.* = a.duplicate(s.engine, typed);
            return c.pi_js_undefined();
        }
    }.body, .{ native_bytes[0..], &external, &backing, &view });
    f.engine.freeValue(ignored);
    defer f.engine.freeValue(backing);
    defer f.engine.freeValue(view);
    var result: buffers.BufferValue = .{};
    try f.convert(&result, view); defer result.deinit();
    try std.testing.expectEqual(@as(usize, 0), external.calls);
    c.JS_DetachArrayBuffer(f.engine.context, backing);
    try std.testing.expectEqual(@as(usize, 1), external.calls);
    try expectBytes(&result, &.{ 1, 2, 3, 4 });
}

test "native BufferValue native heap storage is charged and retired by its own deinit" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const view = try f.evalValue("new Uint8Array(2048).fill(65)");
    defer f.engine.freeValue(view);
    c.JS_RunGC(f.engine.runtime);
    const before = c.pi_js_native_memory_used(f.engine.native_memory_owner);
    var result: buffers.BufferValue = .{};
    try f.convert(&result, view); errdefer result.deinit();
    try std.testing.expect(result.isAllocated());
    try std.testing.expectEqual(@as(usize, 2048), result.bytes().?.len);
    try std.testing.expect(c.pi_js_native_memory_used(f.engine.native_memory_owner) > before);
    result.deinit();
    try std.testing.expectEqual(before, c.pi_js_native_memory_used(f.engine.native_memory_owner));
}

test "native BufferValue rejects a borrowed Environment from another live Engine" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var other: Fixture = undefined; try other.init(); defer other.deinit();
    const input = try f.evalValue("'local'"); defer f.engine.freeValue(input);
    var result: buffers.BufferValue = .{};
    defer result.deinit();
    try std.testing.expectError(error.ActualBufferValueEnvironmentMismatch,
        a.expression(f.engine, struct {
            fn body(s: *a.Scope, target: *buffers.BufferValue,
                environment: *callbacks.Environment, value: c.JSValue) !c.JSValue
            {
                try target.init(s, environment, value);
                return c.pi_js_undefined();
            }
        }.body, .{ &result, other.env(), input }));
    try std.testing.expect(!result.initialized);
    try std.testing.expect(result.bytes() == null);
}

test "native BufferValue empty path namespace is a true no-op with stable stack address" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var result: buffers.BufferValue = .{};
    try f.sourceBuffer(&result, "''"); defer result.deinit();
    const before = result.bytes().?.ptr;
    try f.namespace(&result);
    try expectBytes(&result, "");
    try std.testing.expect(before == result.bytes().?.ptr);
    try std.testing.expectEqual(@as(usize, 1024), result.capacity());
}

test "native BufferValue namespace uses actual private drive Map and preserves POSIX spelling" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var result: buffers.BufferValue = .{};
    defer result.deinit();
    if (builtin.os.tag == .windows) {
        try std.testing.expect(n.pi_node_options_environment_allowed() != 0);
        f.policy.setEnv("=Q:", "Q:\\actual-private-map");
        try f.sourceBuffer(&result, "'Q:child/../leaf/'");
        try f.namespace(&result);
        try expectBytes(&result, "\\\\?\\Q:\\actual-private-map\\leaf");
    } else {
        try f.sourceBuffer(&result, "'/pkg//nested/../entry.js'");
        const before = result.bytes().?.ptr;
        try f.namespace(&result);
        try expectBytes(&result, "/pkg//nested/../entry.js");
        try std.testing.expect(before == result.bytes().?.ptr);
    }
}

test "native BufferValue namespace retains native UNC normalization" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var result: buffers.BufferValue = .{};
    try f.sourceBuffer(&result, "'//server/share/pkg/../entry.js'"); defer result.deinit();
    try f.namespace(&result);
    try expectBytes(&result, if (builtin.os.tag == .windows)
        "\\\\?\\UNC\\server\\share\\entry.js" else "//server/share/pkg/../entry.js");
}

test "native BufferValue namespace preserves embedded NUL as part of the native span" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var result: buffers.BufferValue = .{};
    try f.sourceBuffer(&result, "'Q:/native\\0suffix'"); defer result.deinit();
    try f.namespace(&result);
    try expectBytes(&result, if (builtin.os.tag == .windows)
        "\\\\?\\Q:\\native\x00suffix" else "Q:/native\x00suffix");
}

test "native BufferValue native String copy grows once and does not shrink its charged allocation" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var result: buffers.BufferValue = .{};
    try f.sourceBuffer(&result, "'base'"); defer result.deinit();
    var large: [2048]u8 = @splat('x');
    large[1000] = 0;
    try result.copyFromNative(&large);
    try expectBytes(&result, &large);
    const pointer = result.bytes().?.ptr;
    try result.copyFromNative("short");
    try expectBytes(&result, "short");
    try std.testing.expect(pointer == result.bytes().?.ptr);
    try std.testing.expectEqual(@as(usize, 2049), result.capacity());
}

test "native BufferValue namespace refuses another Engine native context before touching the path" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var other: Fixture = undefined; try other.init(); defer other.deinit();
    var result: buffers.BufferValue = .{};
    try f.sourceBuffer(&result, "'before'"); defer result.deinit();
    try std.testing.expectError(error.ActualOpenFileHandlePathEnvironmentRequired,
        a.expression(f.engine, struct {
            fn body(s: *a.Scope, target: *buffers.BufferValue,
                environment: *const open.abi.PiNodePermissionEnvironment) !c.JSValue
            {
                try path_owner.toNamespacedPath(s, target, environment);
                return c.pi_js_undefined();
            }
        }.body, .{ &result, @as(*const open.abi.PiNodePermissionEnvironment,
            @ptrCast(&other.policy.environment)) }));
    try expectBytes(&result, "before");
}

test "native BufferValue OpenFileHandle pre-request preserves exact Int32 flag and mode extremes" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate("prepareNativeOpenPath('Q:/native',2147483647,-2147483648);");
    try std.testing.expectEqual(@as(c_int, 2147483647), f.prepared_flags);
    try std.testing.expectEqual(@as(c_int, -2147483648), f.prepared_mode);
    try f.evaluate("prepareNativeOpenPath(new Uint8Array([81,58,47,110]),0,511);");
    try std.testing.expectEqual(@as(c_int, 0), f.prepared_flags);
    try std.testing.expectEqual(@as(c_int, 511), f.prepared_mode);
    try f.evaluate("prepareNativeOpenPath('',-2147483648,2147483647);");
    try std.testing.expectEqual(@as(c_int, -2147483648), f.prepared_flags);
    try std.testing.expectEqual(@as(c_int, 2147483647), f.prepared_mode);
    try std.testing.expect(f.active_arguments == null);
}

test "native BufferValue OpenFileHandle denies synchronously with namespaced full resource before request selection" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.policy.enable();
    try f.evaluate(
        \\globalThis.requestTouches=0;
        \\globalThis.futureRequest=new Proxy({}, {get(){requestTouches++;throw "request entered";}});
        \\try { prepareNativeOpenPath("Q:/native\0suffix",nativePathReadOnly,0,futureRequest); }
        \\catch(e) { globalThis.deniedPath=e; }
    );
    try f.expect("requestTouches===0 && deniedPath.code==='ERR_ACCESS_DENIED' && deniedPath.permission==='FileSystemRead'");
    if (builtin.os.tag == .windows)
        try f.expect("deniedPath.resource==='\\\\\\\\?\\\\Q:\\\\native\\0suffix'")
    else
        try f.expect("deniedPath.resource==='Q:/native\\0suffix'");
    try std.testing.expect(f.active_arguments == null);
}

test "native BufferValue OpenFileHandle outer path survives native permission repair nested open preparation and GC" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.policy.enable();
    try f.evaluate(
        \\globalThis.outerNativePath="Q:/"+"x".repeat(2000);
        \\globalThis.pathBefore=null;globalThis.pathAfter=null;globalThis.nestedNativePath=null;
        \\Object.defineProperty(Error.prototype,"code",{configurable:true,set(code){
        \\  pathBefore=inspectNativeOpenPath();
        \\  allowNativePathRead();
        \\  nestedNativePath=prepareNativeOpenPath("Q:/nested",nativePathReadOnly,0);
        \\  collectNativeOpenPath();
        \\  pathAfter=inspectNativeOpenPath();
        \\  Object.defineProperty(this,"code",{value:code,writable:true,configurable:true,enumerable:true});
        \\}});
        \\try { prepareNativeOpenPath(outerNativePath,nativePathReadOnly,0); }
        \\catch(e) { globalThis.outerNativeError=e; }
        \\delete Error.prototype.code;
    );
    try f.expect(
        \\outerNativeError.code==="ERR_ACCESS_DENIED" &&
        \\outerNativeError.resource===pathBefore && pathAfter===pathBefore &&
        \\pathBefore.endsWith("x".repeat(2000)) && nestedNativePath.endsWith("nested")
    );
    try std.testing.expect(f.active_arguments == null);
}

test "native BufferValue OpenFileHandle permission setter exception supersedes denial and releases active path" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.policy.enable();
    try f.evaluate(
        \\globalThis.pathSetterReason={};
        \\Object.defineProperty(Error.prototype,"permission",{configurable:true,set(){
        \\  collectNativeOpenPath();throw pathSetterReason;
        \\}});
        \\try { prepareNativeOpenPath("Q:/native",nativePathReadOnly,0); }
        \\catch(e) { globalThis.pathSetterCaught=e; }
        \\delete Error.prototype.permission;
    );
    try f.expect("pathSetterCaught===pathSetterReason");
    try std.testing.expect(f.active_arguments == null);
}


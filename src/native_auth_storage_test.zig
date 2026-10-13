const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const json = @import("durable/backend/json.zig");
const c = em.c;
fn retiredAllocationFixture(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return em.Engine.fromContext(context.?).throwNativeOutOfMemory();
}

test "native persistent AuthStorage guest out of memory text retains Source best effort fallback" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try @import("extensions/abort_signal.zig").install(engine);
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try @import("extensions/native_auth_storage.zig").install(engine, exports);
    try engine.registerValueModule("native-auth-storage", exports);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "retiredAllocationFixture", try engine.checked(c.JS_NewCFunction(engine.context, retiredAllocationFixture, "retiredAllocationFixture", 0)));
    const retired = try engine.eval("try{retiredAllocationFixture()}catch(error){globalThis.retiredAllocationReason=error}", "retired-auth-allocation", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(retired);
    const generation = engine.native_allocation_generation;
    const module = try engine.evalModule(
        \\import{AuthStorage}from'native-auth-storage';const guest=new InternalError('out of memory');guest.native_allocation_generation=99;for(const reason of[guest,retiredAllocationReason]){const backend={withLock(fn){return fn('{"fixture":{"type":"oauth","access":"fixture","refresh":"fixture","expires":1}}').result},withLockAsync(){return Promise.reject(reason)}};const store=AuthStorage.fromStorage(backend);backend.withLock=()=>{throw reason};store.reload();const value=await store.read('fixture');if(value.access!=='fixture')throw Error('guest fallback lost');let observed;try{await store.read('fixture',{signal:new AbortController().signal})}catch(error){observed=error}if(observed!==reason)throw Error('guest failure identity lost')}export const proof=true;
    , "native-auth-guest-error-provenance");
    engine.freeValue(module);
    try std.testing.expectEqual(generation, engine.native_allocation_generation);
}

test "native persistent AuthStorage actual Source12 readonly validation cache clone and raw reads" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(std.testing.io, &path);
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/abort_signal.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/node_fs.zig").install(engine, std.testing.io);
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try @import("extensions/native_auth_storage.zig").install(engine, exports);
    try engine.registerValueModule("native-auth-storage", exports);
    var fixture = try json.Owned.parse(std.testing.allocator, @embedFile("durable/fixtures/durable-19cb534-auth-readonly-source.json"));
    defer fixture.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "authReadonlySource", try @import("extensions/native_durable.zig").jsValue(engine, fixture.value));
    try sdk.put(engine, global, "authFixtureRoot", try sdk.text(engine, path[0..length]));
    const module = engine.evalModule(@embedFile("durable/fixtures/durable-19cb534-auth-readonly-native.input.txt"), "native-auth-readonly-source12") catch |err| {
        std.debug.print("Native readonly AuthStorage {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "none" });
        return err;
    };
    engine.freeValue(module);
    c.JS_RunGC(engine.runtime);
}

// Test-only bindings for filesystem methods not yet exposed by node:fs.
// They touch only an empty .lock directory below this test's owned tmpDir.
fn fixtureDirectory(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return directoryOperation(engine, args[0..@intCast(argc)], magic, captures[0]) catch |err| @import("extensions/native_durable.zig").reject(engine, err);
}
fn directoryOperation(engine: *em.Engine, args: []const c.JSValue, magic: c_int, root: c.JSValue) !c.JSValue {
    if (args.len == 0) return error.MissingFixtureDirectory;
    const candidate = try engine.toString(args[0]);
    defer engine.gpa.free(candidate);
    const path = try std.fs.path.resolve(engine.gpa, &.{candidate});
    defer engine.gpa.free(path);
    const owned = try engine.toString(root);
    defer engine.gpa.free(owned);
    if (path.len <= owned.len or !std.ascii.eqlIgnoreCase(path[0..owned.len], owned) or (path[owned.len] != '/' and path[owned.len] != '\\') or !std.mem.endsWith(u8, path, ".lock")) return error.FixtureDirectoryEscaped;
    if (magic == 0) {
        try std.Io.Dir.cwd().deleteDir(std.testing.io, path);
    } else if (magic == 2) {
        const stat = try std.Io.Dir.cwd().statFile(std.testing.io, path, .{});
        const value = try sdk.object(engine);
        errdefer engine.freeValue(value);
        try sdk.put(engine, value, "mtimeMs", c.JS_NewFloat64(engine.context, @as(f64, @floatFromInt(stat.mtime.nanoseconds)) / std.time.ns_per_ms));
        return value;
    } else {
        if (args.len != 3) return error.MissingFixtureTimestamp;
        var milliseconds: f64 = 0;
        if (c.JS_ToFloat64(engine.context, &milliseconds, args[2]) < 0) return error.JavaScriptException;
        if (!std.math.isFinite(milliseconds)) return error.InvalidFixtureTimestamp;
        const timestamp: std.Io.Timestamp = .{ .nanoseconds = @intFromFloat(milliseconds * std.time.ns_per_ms) };
        try @import("extensions/native_auth_file_io.zig").setTimestamp(engine.gpa, std.testing.io, path, timestamp);
    }
    return c.pi_js_undefined();
}

test "native persistent AuthStorage actual Source8 held locks abort stale and alternating paths" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(std.testing.io, &path);
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/abort_signal.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/node_fs.zig").install(engine, std.testing.io);
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try @import("extensions/native_auth_storage.zig").install(engine, exports);
    try engine.registerValueModule("native-auth-storage", exports);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const root = try sdk.text(engine, path[0..length]);
    defer engine.freeValue(root);
    try sdk.put(engine, global, "authFixtureRoot", c.JS_DupValue(engine.context, root));
    var captures = [_]c.JSValue{root};
    inline for (.{ "nativeAuthTestRmdir", "nativeAuthTestUtimes" }, 0..) |name, magic| {
        try sdk.put(engine, global, name, try engine.checked(c.JS_NewCFunctionData2(engine.context, fixtureDirectory, name, if (magic == 0) 1 else 3, @intCast(magic), captures.len, &captures)));
    }
    var fixture = try json.Owned.parse(std.testing.allocator, @embedFile("durable/fixtures/durable-19cb534-auth-locks-multipath-source.json"));
    defer fixture.deinit();
    try sdk.put(engine, global, "authLocksSource", try @import("extensions/native_durable.zig").jsValue(engine, fixture.value));
    const module = engine.evalModule(@embedFile("durable/fixtures/durable-19cb534-auth-locks-multipath-native.input.txt"), "native-auth-locks-multipath-source8") catch |err| {
        std.debug.print("Native persistent locks {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "none" });
        return err;
    };
    engine.freeValue(module);
    c.JS_RunGC(engine.runtime);
}

test "native persistent AuthStorage actual Source heartbeat owner pumping before external callback release" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(std.testing.io, &path);
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/node_fs.zig").install(engine, std.testing.io);
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try @import("extensions/native_auth_storage.zig").install(engine, exports);
    try engine.registerValueModule("native-auth-storage", exports);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const root = try sdk.text(engine, path[0..length]);
    defer engine.freeValue(root);
    try sdk.put(engine, global, "authFixtureRoot", c.JS_DupValue(engine.context, root));
    var captures = [_]c.JSValue{root};
    try sdk.put(engine, global, "nativeAuthTestUtimes", try engine.checked(c.JS_NewCFunctionData2(engine.context, fixtureDirectory, "nativeAuthTestUtimes", 3, 1, captures.len, &captures)));
    try sdk.put(engine, global, "nativeAuthTestStat", try engine.checked(c.JS_NewCFunctionData2(engine.context, fixtureDirectory, "nativeAuthTestStat", 1, 2, captures.len, &captures)));
    var fixture = try json.Owned.parse(std.testing.allocator, @embedFile("durable/fixtures/durable-19cb534-auth-heartbeat-source.json"));
    defer fixture.deinit();
    try sdk.put(engine, global, "authHeartbeatSource", try @import("extensions/native_durable.zig").jsValue(engine, fixture.value));
    const started = try engine.evalModule(@embedFile("durable/fixtures/durable-19cb534-auth-heartbeat-native.input.txt"), "native-auth-heartbeat-start");
    engine.freeValue(started);
    const ready = try sdk.get(engine, global, "heartbeatReady");
    defer engine.freeValue(ready);
    const entered = try engine.awaitValue(ready);
    engine.freeValue(entered);
    const changed = try engine.eval("nativeAuthTestUtimes(heartbeatCompromisedPath,new Date(Date.now()-1000),new Date(Date.now()-1000))", "native-auth-heartbeat-mtime", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(changed);
    const pending = try sdk.get(engine, global, "heartbeatPending");
    defer engine.freeValue(pending);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, pending));
    // The callback is externally held; no host await is active during this
    // real passage of time. Pump the now-due owner timers, then release both
    // callbacks. The final await retains the unchanged 10s host deadline.
    try std.testing.expect(engine.host_await_deadline_ms == null);
    try std.testing.io.sleep(.fromMilliseconds(16100), .awake);
    const pump = engine.host_pump orelse return error.NativeTimerPumpMissing;
    try std.testing.expect(try pump(engine));
    try std.testing.expect(try pump(engine));
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, pending));
    const finished = engine.evalModule("await heartbeatFinish();export const proof=true;", "native-auth-heartbeat-finish") catch |err| {
        std.debug.print("Native heartbeat AuthStorage {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "none" });
        return err;
    };
    engine.freeValue(finished);
}

test "native persistent AuthStorage heartbeat directory timestamp releases every failed native allocation" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const fileio = @import("extensions/native_auth_file_io.zig");
            var tmp = std.testing.tmpDir(.{});
            defer tmp.cleanup();
            var path: [std.Io.Dir.max_path_bytes]u8 = undefined;
            const length = try tmp.dir.realPath(std.testing.io, &path);
            const lock = try std.fs.path.join(gpa, &.{ path[0..length], "auth.json.lock" });
            defer gpa.free(lock);
            var lease: fileio.Lease = .{ .gpa = gpa, .io = std.testing.io, .path = lock };
            defer fileio.release(&lease);
            try std.testing.expect(try fileio.tryAcquire(&lease, 30000, std.Io.Clock.real.now(std.testing.io).toMilliseconds()));
            try fileio.heartbeat(&lease);
            try std.testing.expect(lease.owned and !lease.compromised);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}

test "native persistent AuthStorage actual Source8 real files cache env and cancellation" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(std.testing.io, &path);
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/abort_signal.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/node_fs.zig").install(engine, std.testing.io);
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try @import("extensions/native_auth_storage.zig").install(engine, exports);
    try engine.registerValueModule("native-auth-storage", exports);
    var fixture = try json.Owned.parse(std.testing.allocator, @embedFile("durable/fixtures/durable-19cb534-auth-persistence-source.json"));
    defer fixture.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "authPersistenceSource", try @import("extensions/native_durable.zig").jsValue(engine, fixture.value));
    try sdk.put(engine, global, "authFixtureRoot", try sdk.text(engine, path[0..length]));
    const module = engine.evalModule(@embedFile("durable/fixtures/durable-19cb534-auth-persistence-native.input.txt"), "native-auth-persistence-source8") catch |err| {
        std.debug.print("Native persistent AuthStorage {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "none" });
        return err;
    };
    defer engine.freeValue(module);
    const observed = try sdk.get(engine, global, "authPersistenceActual");
    defer engine.freeValue(observed);
    const raw = try engine.stringify(observed);
    defer engine.gpa.free(raw);
    std.debug.print("Native persistent AuthStorage raw {s}\n", .{raw});
    c.JS_RunGC(engine.runtime);
}

test "native persistent AuthStorage file mutation releases every failed host allocation and lock" {
    const Probe = struct {
        fn exercise(gpa: std.mem.Allocator, path: []const u8) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            engine.native_io = std.testing.io;
            try @import("extensions/abort_signal.zig").install(engine);
            try @import("extensions/timers.zig").install(engine, std.testing.io);
            const exports = try sdk.object(engine);
            defer engine.freeValue(exports);
            try @import("extensions/native_auth_storage.zig").install(engine, exports);
            try engine.registerValueModule("native-auth-storage", exports);
            const global = c.JS_GetGlobalObject(engine.context);
            defer engine.freeValue(global);
            try sdk.put(engine, global, "authFixtureFile", try sdk.text(engine, path));
            const generation = engine.native_allocation_generation;
            const module = engine.evalModule(
                \\import{AuthStorage}from'native-auth-storage';const store=AuthStorage.create(authFixtureFile),credential={type:'api_key',key:'fixture-allocation-key',extra:true};const written=await store.modify('fixture',async()=>credential);if(written!==credential||(await store.read('fixture')).key!==credential.key)throw Error('persistent credential changed');await store.delete('fixture');if(await store.read('fixture')!==undefined)throw Error('persistent delete changed');export const proof=true;
            , "native-auth-persistence-allocation") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(module);
            c.JS_RunGC(engine.runtime);
        }
        fn run(gpa: std.mem.Allocator) !void {
            var tmp = std.testing.tmpDir(.{});
            defer tmp.cleanup();
            var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
            const length = try tmp.dir.realPath(std.testing.io, &buffer);
            const path = try std.fs.path.join(std.testing.allocator, &.{ buffer[0..length], "auth.json" });
            defer std.testing.allocator.free(path);
            var failure: ?anyerror = null;
            exercise(gpa, path) catch |err| {
                failure = err;
            };
            // Runtime finalization must release its lease even when an
            // allocation failed after mkdir and before promise settlement.
            if (tmp.dir.statFile(std.testing.io, "auth.json.lock", .{})) |_| {
                return error.AuthLockRetainedAfterRuntimeCleanup;
            } else |err| if (err != error.FileNotFound) return err;
            if (failure) |err| return err;
            const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
            if (failing.has_induced_failure) {
                std.debug.print("Persistent auth swallowed host allocation index={d}\n", .{failing.fail_index});
                const trace = failing.getStackTrace();
                std.debug.dumpStackTrace(&trace);
            }
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}

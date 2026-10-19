//! Genuine FileAuthStorageBackend + actual native directory-lock/FS/timers.
//! SOURCE ONLY. These tests have not been compiled, queried or executed.
const std = @import("std");
const em = @import("extensions/engine.zig");
const v = @import("extensions/native_ai_provider_values.zig");
const c = em.c;
const sdk = @import("extensions/native_sdk.zig");
fn publish(engine: *em.Engine, name: [*:0]const u8, value: c.JSValue) !void {
    const global = try engine.checked(c.JS_GetGlobalObject(engine.context));
    defer engine.freeValue(global);
    try sdk.put(engine, global, name, c.JS_DupValue(engine.context, value));
}
fn prepare(engine: *em.Engine, root: []const u8) !void {
    engine.native_io = std.testing.io;
    // Real native process publisher, explicit owned test environment. No
    // hand-built global process or Node-version facade is substituted.
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try environment.put("HOME", root);
    try environment.put("USERPROFILE", root);
    try environment.put("PI_CODING_AGENT_DIR", root);
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"actual-auth-file-control"});
    try @import("extensions/abort_signal.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const subject = try @import("extensions/native_auth_file_storage_backend.zig").createDefault(engine);
    defer engine.freeValue(subject);
    try publish(engine, "ActualFileAuthStorageBackend", subject);
    var scope: v.Scope = .{ .engine = engine }; defer scope.deinit();
    const prototype = try scope.get(subject, "prototype");
    inline for (.{ "acquireLockAsync", "withLockAsync" }) |name| {
        const method = try scope.get(prototype, name);
        try std.testing.expect(c.JS_IsAsyncFunction(method));
        try std.testing.expect(!c.JS_IsConstructor(engine.context, method));
    }
    const lock = try scope.own(try @import("extensions/native_auth_directory_lock.zig").create(engine));
    try std.testing.expect(c.JS_IsAsyncFunction(lock));
    try std.testing.expect(!c.JS_IsConstructor(engine.context, lock));
    try std.testing.expect(scope.equal(lock, try scope.get(lock, "lock")));
    try publish(engine, "actualDirectoryLock", lock);
    try publish(engine, "ownedFileFixtureRoot", try scope.text(root));
}
fn observed(engine: *em.Engine, tail: []const u8) !c.JSValue {
    const source = try std.mem.concat(engine.gpa, u8, &.{ @embedFile("extensions/fixtures/auth-file-storage-genuine-af-observer.mjs"), "\n", tail });
    defer engine.gpa.free(source);
    return engine.evalModule(source, "actual-file-auth-genuine-af-controls.mjs");
}
fn markedData(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    _ = engine.throwNativeOutOfMemory();
    const value = c.JS_GetException(context);
    c.JS_SetUncatchableError(context, value);
    return value; // Successful DATA; no actual pending event remains.
}
fn throwCurrent(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return em.Engine.fromContext(context.?).throwNativeOutOfMemoryFatal();
}
fn unmarkedData(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    _ = em.Engine.fromContext(context.?).throwNativeOutOfMemory();
    return c.JS_GetException(context); // A successful unmarked private DATA value.
}
fn throwRawCurrent(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return em.Engine.fromContext(context.?).throwNativeOutOfMemory();
}
fn actualGc(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    c.JS_RunGC(em.Engine.fromContext(context.?).runtime);
    return c.pi_js_undefined();
}
const Case = enum { observer, data, lock_await, current, historical, fresh_getter, lock_historical, push_retirement };
fn run(comptime kind: Case) !void {
    var tmp = std.testing.tmpDir(.{}); defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(std.testing.io, &buffer);
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try prepare(engine, buffer[0..length]);
    const suppression = engine.native_exception_diagnostics_suppressed;
    const invocation = engine.native_fatal_invocation;
    if (kind == .data or kind == .historical or kind == .lock_historical) {
        const fn_value = try engine.checked(c.JS_NewCFunction(engine.context, if (kind == .data) markedData else unmarkedData, "actualMarkedData", 0));
        defer engine.freeValue(fn_value);
        try publish(engine, "actualMarkedData", fn_value);
    }
    if (kind == .current or kind == .fresh_getter) {
        const fn_value = try engine.checked(c.JS_NewCFunction(engine.context, if (kind == .current) throwCurrent else throwRawCurrent, "actualCurrentFailure", 0));
        defer engine.freeValue(fn_value);
        try publish(engine, "actualCurrentFailure", fn_value);
    }
    if (kind == .push_retirement) {
        const fn_value = try engine.checked(c.JS_NewCFunction(engine.context, actualGc, "actualGc", 0));
        defer engine.freeValue(fn_value);
        try publish(engine, "actualGc", fn_value);
        const prior = try engine.eval(
            \\(()=>{let target={retirement:'prior job'};globalThis.weakPushTemporary=new WeakRef(target);
            \\globalThis.takePushTemporary=()=>{const result=target;target=undefined;return result}})();
        , "prior-job-push-temporary", c.JS_EVAL_TYPE_GLOBAL);
        engine.freeValue(prior);
        // WeakRef and its initial keep-alive were created in the prior job.
        // No WeakRef construction/deref occurs during the tested expression
        // until after the actual GC observation in the iterator getter.
        c.JS_ClearKeptObjects(engine.runtime);
    }
    const source: []const u8 = switch (kind) {
        .observer => "export const observations=await observeFileBackend(ActualFileAuthStorageBackend,ownedFileFixtureRoot);",
        .data => "export const observations=await verifyFileRejectedData(ActualFileAuthStorageBackend,ownedFileFixtureRoot,actualMarkedData);",
        .lock_await =>
            \\const b=new ActualFileAuthStorageBackend(path.join(ownedFileFixtureRoot,'lock-shape.json'));
            \\b.ensureParentDir();b.ensureFileExists();
            \\const NativePromise=globalThis.Promise;let rawRelease,allow,settled=false,constructions=0;
            \\globalThis.Promise=new Proxy(NativePromise,{construct(target,args,newTarget){
            \\  constructions++;const executor=args[0];
            \\  return Reflect.construct(target,[(resolve,reject)=>executor(value=>{rawRelease=value;allow=()=>resolve(value)},reject)],newTarget);
            \\}});
            \\const pending=actualDirectoryLock.lock(b.authPath,{realpath:false,retries:0,stale:30000});
            \\pending.then(()=>{settled=true});
            \\for(let i=0;i<100&&typeof allow!=='function';i++)await new NativePromise(resolve=>setTimeout(resolve,0));
            \\assert(typeof allow==='function','actual callback lock did not progress');
            \\assert(!settled&&constructions===1,'genuine inner Await must be held');
            \\assert(typeof rawRelease==='function'&&rawRelease.length===1&&!Object.hasOwn(rawRelease,'prototype'),'raw callback release shape');
            \\allow();const release=await pending;
            \\assert(release!==rawRelease&&release.length===0&&release.name===''&&!Object.hasOwn(release,'prototype'),'ordinary toPromise release shape');
            \\assert(Object.prototype.toString.call(release)==='[object Function]','release must remain ordinary');
            \\globalThis.Promise=NativePromise;await release();
            \\export const observations={constructions,settled,publicAlias:actualDirectoryLock.lock===actualDirectoryLock};
        ,
        .current =>
            \\const b=new ActualFileAuthStorageBackend(path.join(ownedFileFixtureRoot,'current-fatal.json'));
            \\globalThis.actualAfterCurrent=0;
            \\b.ensureParentDir=function(){actualAfterCurrent++;throw Error('must not enter')};
            \\await b.withLockAsync(async()=>({result:0}),{signal:{throwIfAborted:actualCurrentFailure}});
            \\export const unexpected=true;
        ,
        .historical =>
            \\const b=new ActualFileAuthStorageBackend(path.join(ownedFileFixtureRoot,'historical-two-ops.json'));
            \\let data,releases=0;overrideAcquire(b,function(){releases++;return Promise.resolve()});
            \\const outcome={get result(){data=actualMarkedData();return data},get next(){throw data}};
            \\let caught;try{await b.withLockAsync(async()=>outcome)}catch(reason){caught=reason}
            \\assert(caught===data&&releases===1,'later getter must not reclassify earlier successful private DATA');
            \\export const observations={sameReason:caught===data,releases};
        ,
        .fresh_getter =>
            \\const b=new ActualFileAuthStorageBackend(path.join(ownedFileFixtureRoot,'fresh-next-getter.json'));
            \\globalThis.actualAfterCurrent=0;overrideAcquire(b,function(){actualAfterCurrent++;return Promise.resolve()});
            \\const outcome={result:1};Object.defineProperty(outcome,'next',{get:actualCurrentFailure});
            \\await b.withLockAsync(async()=>outcome);
            \\export const unexpected=true;
        ,
        .lock_historical =>
            \\const b=new ActualFileAuthStorageBackend(path.join(ownedFileFixtureRoot,'lock-historical.json'));
            \\b.ensureParentDir();b.ensureFileExists();let data,caught;
            \\const options={realpath:false,retries:0,get stale(){data=actualMarkedData();return 30000},get update(){throw data}};
            \\try{await actualDirectoryLock.lock(b.authPath,options)}catch(reason){caught=reason}
            \\assert(caught===data,'callback adapter must not reclassify earlier successful option DATA');
            \\export const observations={sameReason:caught===data};
        ,
        .push_retirement =>
            \\const b=new ActualFileAuthStorageBackend(path.join(ownedFileFixtureRoot,'push-retirement.json'));
            \\b.ensureParentDir();b.ensureFileExists();
            \\const originalPush=Array.prototype.push;
            \\const originalDescriptor=Object.getOwnPropertyDescriptor(Array.prototype,Symbol.iterator);
            \\let inspected=false,retired=false;
            \\Array.prototype.push=function(...values){originalPush.apply(this,values);return takePushTemporary()};
            \\Object.defineProperty(Array.prototype,Symbol.iterator,{configurable:true,get(){
            \\  if(!inspected){actualGc();retired=weakPushTemporary.deref()===undefined;inspected=true}
            \\  return originalDescriptor.value;
            \\}});
            \\const pending=actualDirectoryLock.lock(b.authPath,{realpath:false,retries:0,stale:30000});
            \\assert(inspected&&retired,'push return must retire before iterable getter');
            \\Array.prototype.push=originalPush;Object.defineProperty(Array.prototype,Symbol.iterator,originalDescriptor);
            \\const release=await pending;await release();
            \\export const observations={inspected,retired};
        ,
    };
    const evaluated = observed(engine, source);
    if (kind == .current or kind == .fresh_getter) {
        if (evaluated) |value| { engine.freeValue(value); return error.ExpectedActualFileAuthCurrentFatal; }
        else |err| if (err != error.JavaScriptException) return err;
        const reason = engine.captured_exception orelse return error.MissingActualFileAuthCurrentFatal;
        try std.testing.expect(c.JS_IsUncatchableError(reason));
        try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
        const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
        const count = c.JS_GetPropertyStr(engine.context, global, "actualAfterCurrent"); defer engine.freeValue(count);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, count, c.JS_NewInt32(engine.context, 0)));
    } else {
        engine.freeValue(try evaluated);
        try std.testing.expect(!c.JS_HasException(engine.context));
        try std.testing.expect(engine.captured_exception == null);
    }
    try std.testing.expectEqual(suppression, engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(engine.native_fatal_invocation == invocation);
}
test "Auth file genuine AF actual IO held callback finally and ordinary identity" { try run(.observer); }
test "Auth file genuine AF rejected marked DATA runs real Source finally" { try run(.data); }
test "Auth file genuine AF proper lock real inner Await and ordinary release" { try run(.lock_await); }
test "Auth file genuine AF actual current fatal bypasses downstream Source work" { try run(.current); }
test "Auth file genuine AF earlier successful private DATA later thrown stays ordinary" { try run(.historical); }
test "Auth file genuine AF fresh private failure in actual next getter stays fatal" { try run(.fresh_getter); }
test "Auth file genuine AF proper lock earlier option DATA later thrown stays ordinary" { try run(.lock_historical); }
test "Auth file genuine AF adapter push prior-job weak temporary retires before iterator" { try run(.push_retirement); }

const Cleanup = enum { ordinary, fatal, raw_pending };
const Probe = struct {
    engine: *em.Engine,
    class: c.JSClassID = 0,
    cleanup: Cleanup,
    ordinary: c.JSValue,
    fatal: c.JSValue,
    first_fatal: c.JSValue,
    failing: ?*std.testing.FailingAllocator = null,
    initially_marked: bool = false,
    raw_generation_before: u64 = 0,
    raw_generation_after: u64 = 0,
    push_getters: usize = 0,
    push_calls: usize = 0,
    references: usize = 1,
    finalized: usize = 0,
};
threadlocal var active: ?*Probe = null;
fn releaseProbe(p: *Probe) void {
    p.references -= 1;
    if (p.references != 0) return;
    p.engine.freeValue(p.ordinary);
    p.engine.freeValue(p.fatal);
    p.engine.freeValue(p.first_fatal);
    p.engine.gpa.destroy(p);
}
fn retireCarrier(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const p: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    defer releaseProbe(p);
    p.finalized += 1;
    if (p.failing != null and c.JS_IsUndefined(p.first_fatal)) {
        // Observe the actual trusted host OOM producer already published by
        // the root-admission boundary, BEFORE this finalizer emits B.
        if (p.engine.native_allocation_exception) |reason| p.first_fatal = c.JS_DupValue(p.engine.context, reason);
    }
    if (p.cleanup == .ordinary) {
        _ = c.JS_Throw(p.engine.context, c.JS_DupValue(p.engine.context, p.ordinary));
    } else {
        p.raw_generation_before = p.engine.native_allocation_generation;
        if (p.cleanup == .fatal) _ = p.engine.throwNativeOutOfMemoryFatal() else _ = p.engine.throwNativeOutOfMemory();
        p.raw_generation_after = p.engine.native_allocation_generation;
        const reason = c.JS_GetException(p.engine.context);
        p.initially_marked = c.JS_IsUncatchableError(reason);
        if (c.JS_IsUndefined(p.fatal)) p.fatal = c.JS_DupValue(p.engine.context, reason);
        _ = c.JS_Throw(p.engine.context, reason);
    }
}
fn soleCarrier(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const p = active orelse return c.JS_ThrowInternalError(context, "missing owned carrier control");
    const value = c.JS_NewObjectClass(context, p.class);
    if (c.JS_IsException(value)) return value;
    p.references += 1;
    _ = c.JS_SetOpaque(value, p);
    if (p.failing) |failing| failing.fail_index = failing.alloc_index;
    return value;
}
fn retirement(comptime kind: Cleanup) !void {
    var tmp = std.testing.tmpDir(.{}); defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(std.testing.io, &buffer);
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    try prepare(engine, buffer[0..length]);
    const p = try engine.gpa.create(Probe);
    p.* = .{ .engine = engine, .fatal = c.pi_js_undefined(), .first_fatal = c.pi_js_undefined(), .ordinary = try engine.checked(c.JS_NewError(engine.context)), .cleanup = kind };
    defer releaseProbe(p);
    _ = c.JS_NewClassID(engine.runtime, &p.class);
    const definition: c.JSClassDef = .{ .class_name = "File backend sole result carrier", .finalizer = retireCarrier };
    if (c.JS_NewClass(engine.runtime, p.class, &definition) < 0) return error.OutOfMemory;
    const getter = try engine.checked(c.JS_NewCFunction(engine.context, soleCarrier, "soleCarrier", 0)); defer engine.freeValue(getter);
    try publish(engine, "actualSoleCarrier", getter);
    active = p; defer active = null;
    const generation = engine.native_allocation_generation;
    const suppression = engine.native_exception_diagnostics_suppressed;
    const invocation = engine.native_fatal_invocation;
    const evaluated = observed(engine,
        \\const b=new ActualFileAuthStorageBackend(path.join(ownedFileFixtureRoot,'native-retirement.json'));
        \\globalThis.actualCleanupCoercions=0;globalThis.actualCleanupReleases=0;
        \\const original={toString(){actualCleanupCoercions++;return 'ordinary A'}};
        \\const unlock=held();overrideAcquire(b,function(){actualCleanupReleases++;return unlock.promise});
        \\const outcome={get result(){return actualSoleCarrier()},get next(){throw original}};
        \\let settled=false,caught;const pending=b.withLockAsync(async()=>outcome).catch(reason=>{settled=true;caught=reason});
        \\await until(()=>actualCleanupReleases===1);
        \\assert(!settled,'native try roots retire before real finally Await, not after');
        \\unlock.resolve();await pending;
        \\assert(caught===original&&actualCleanupReleases===1&&actualCleanupCoercions===0,'ordinary completion survives native cleanup and real finally');
        \\export const proof=true;
    );
    if (kind == .ordinary) {
        engine.freeValue(try evaluated);
        try std.testing.expect(engine.captured_exception == null and !c.JS_HasException(engine.context));
    } else {
        if (evaluated) |value| { engine.freeValue(value); return error.ExpectedActualFileRetirementFatal; }
        else |err| if (err != error.JavaScriptException) return err;
        const actual = c.JS_DupValue(engine.context, engine.captured_exception orelse return error.MissingActualFileRetirementFatal); defer engine.freeValue(actual);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, p.fatal));
        try std.testing.expect(c.JS_IsUncatchableError(actual));
        if (kind == .raw_pending) try std.testing.expect(!p.initially_marked);
        const tag = c.pi_js_native_allocation_error_generation(actual);
        try std.testing.expect(tag != 0 and tag -% generation != 0 and tag -% generation <= engine.native_allocation_generation -% generation);
        const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
        inline for (.{ "actualCleanupCoercions", "actualCleanupReleases" }) |name| {
            const count = c.JS_GetPropertyStr(engine.context, global, name); defer engine.freeValue(count);
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, count, c.JS_NewInt32(engine.context, 0)));
        }
    }
    try std.testing.expectEqual(@as(usize, 1), p.finalized);
    try std.testing.expectEqual(suppression, engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(engine.native_fatal_invocation == invocation);
}
test "Auth file genuine AF sole result ordinary cleanup before held finally" { try retirement(.ordinary); }
test "Auth file genuine AF sole result new fatal skips guest finally" { try retirement(.fatal); }
test "Auth file genuine AF sole result raw pending OOM exact retirement boundary" { try retirement(.raw_pending); }

fn overflow(comptime cleanup: Cleanup) !void {
    var tmp = std.testing.tmpDir(.{}); defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(std.testing.io, &buffer);
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try em.Engine.init(failing.allocator(), .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    try prepare(engine, buffer[0..length]);
    const p = try engine.gpa.create(Probe);
    p.* = .{ .engine = engine, .fatal = c.pi_js_undefined(), .first_fatal = c.pi_js_undefined(), .ordinary = try engine.checked(c.JS_NewError(engine.context)), .cleanup = cleanup, .failing = &failing };
    defer releaseProbe(p);
    _ = c.JS_NewClassID(engine.runtime, &p.class);
    const definition: c.JSClassDef = .{ .class_name = "Actual Auth spread root overflow carrier", .finalizer = retireCarrier };
    if (c.JS_NewClass(engine.runtime, p.class, &definition) < 0) return error.OutOfMemory;
    const getter = try engine.checked(c.JS_NewCFunction(engine.context, soleCarrier, "actualOverflowCarrier", 0)); defer engine.freeValue(getter);
    try publish(engine, "actualOverflowCarrier", getter);
    active = p; defer active = null;
    const generation = engine.native_allocation_generation;
    const suppression = engine.native_exception_diagnostics_suppressed;
    const invocation = engine.native_fatal_invocation;
    const evaluated = observed(engine,
        \\const b=new ActualFileAuthStorageBackend(path.join(ownedFileFixtureRoot,'actual-root-overflow.json'));
        \\b.ensureParentDir();b.ensureFileExists();globalThis.actualAfterOverflow=0;
        \\Object.defineProperty(Array.prototype,Symbol.iterator,{configurable:true,writable:true,value:function(){
        \\  const args=this;let index=0;return {next(){index++;
        \\    if(index<=3)return {done:false,value:args[index-1]};
        \\    if(index<=32)return {done:false,value:0};
        \\    if(index===33)return {done:false,get value(){return actualOverflowCarrier()}};
        \\    return {done:true};
        \\  }};
        \\}});
        \\await actualDirectoryLock.lock(b.authPath,{realpath:false,retries:0,stale:30000});
        \\actualAfterOverflow++;export const unexpected=true;
    );
    // No allocator failure is left armed during host assertions/teardown.
    failing.fail_index = std.math.maxInt(usize);
    if (evaluated) |value| { engine.freeValue(value); return error.ExpectedActualRootAppendFailure; }
    else |err| if (err != error.JavaScriptException) return err;
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(@as(usize, 1), p.finalized);
    const actual = c.JS_DupValue(engine.context, engine.captured_exception orelse return error.MissingActualRootAppendFailure); defer engine.freeValue(actual);
    try std.testing.expect(c.JS_IsObject(p.first_fatal));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, p.first_fatal));
    try std.testing.expect(c.JS_IsUncatchableError(actual));
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, actual, p.ordinary));
    const tag = c.pi_js_native_allocation_error_generation(actual);
    try std.testing.expect(tag != 0 and tag -% generation != 0 and tag -% generation <= engine.native_allocation_generation -% generation);
    if (cleanup == .raw_pending) {
        try std.testing.expect(c.JS_IsObject(p.fatal));
        // The guarded Engine producer preserves independently retained A. It
        // does not create a fresh B beneath an already-held native fatal.
        try std.testing.expect(p.initially_marked);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, p.fatal));
        try std.testing.expectEqual(p.raw_generation_before, p.raw_generation_after);
    }
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    const count = c.JS_GetPropertyStr(engine.context, global, "actualAfterOverflow"); defer engine.freeValue(count);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, count, c.JS_NewInt32(engine.context, 0)));
    try std.testing.expectEqual(suppression, engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(engine.native_fatal_invocation == invocation);
}
test "Auth file genuine AF actual spread root append GPA OOM precedes ordinary carrier cleanup" { try overflow(.ordinary); }
test "Auth file genuine AF actual spread root append GPA OOM survives guarded cleanup producer without new birth" { try overflow(.raw_pending); }

fn armPushGetter(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const p = active orelse return c.JS_ThrowInternalError(context, "missing push order control");
    p.push_getters += 1;
    const failing = p.failing orelse return c.JS_ThrowInternalError(context, "missing actual allocator");
    failing.fail_index = failing.alloc_index;
    return c.JS_DupValue(context, roots[0]);
}
fn delegatedPush(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const p = active orelse return c.JS_ThrowInternalError(context, "missing push order control");
    p.push_calls += 1;
    return c.JS_Call(context, roots[0], receiver, argc, args); // Actual original push.
}
test "Auth file genuine AF adapter push getter precedes real callback allocation failure" {
    var tmp = std.testing.tmpDir(.{}); defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(std.testing.io, &buffer);
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try em.Engine.init(failing.allocator(), .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    try prepare(engine, buffer[0..length]);
    const p = try engine.gpa.create(Probe);
    p.* = .{ .engine = engine, .fatal = c.pi_js_undefined(), .first_fatal = c.pi_js_undefined(), .ordinary = c.pi_js_undefined(), .cleanup = .ordinary, .failing = &failing };
    defer releaseProbe(p);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const original = try s.get(try s.get(try s.global("Array"), "prototype"), "push");
    var original_roots = [_]c.JSValue{original};
    const delegate = try s.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, delegatedPush, "delegated actual push", 1, 0, original_roots.len, &original_roots)));
    var delegate_roots = [_]c.JSValue{delegate};
    const getter = try s.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, armPushGetter, "get push", 0, 0, delegate_roots.len, &delegate_roots)));
    try publish(engine, "actualPushGetter", getter);
    active = p; defer active = null;
    const suppression = engine.native_exception_diagnostics_suppressed;
    const invocation = engine.native_fatal_invocation;
    const evaluated = observed(engine,
        \\const b=new ActualFileAuthStorageBackend(path.join(ownedFileFixtureRoot,'actual-push-order.json'));
        \\b.ensureParentDir();b.ensureFileExists();
        \\Object.defineProperty(Array.prototype,'push',{configurable:true,get:actualPushGetter});
        \\await actualDirectoryLock.lock(b.authPath,{realpath:false,retries:0,stale:30000});
        \\export const unexpected=true;
    );
    failing.fail_index = std.math.maxInt(usize);
    if (evaluated) |value| { engine.freeValue(value); return error.ExpectedActualCallbackAllocationFailure; }
    else |err| if (err != error.JavaScriptException) return err;
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(@as(usize, 1), p.push_getters);
    try std.testing.expectEqual(@as(usize, 0), p.push_calls);
    try std.testing.expect(c.JS_IsUncatchableError(engine.captured_exception orelse return error.MissingActualCallbackAllocationFailure));
    try std.testing.expectEqual(suppression, engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(engine.native_fatal_invocation == invocation);
}

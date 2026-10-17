//! Prepared executable controls over the real native management helper.
//! Owned guest fetch inputs test this helper boundary, not HTTP transport.
const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
fn setup(engine: *em.Engine) !void {
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/native_web_fetch.zig").install(engine);
}
test "SDK management HTTP real AF module identity and original caller semantics" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    try setup(engine);
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const first = try s.own(try @import("extensions/native_sdk_management_http.zig").create(engine));
    const second = try s.own(try @import("extensions/native_sdk_management_http.zig").create(engine));
    try std.testing.expect(s.equal(first, second));
    const function = try s.get(first, "fetchWithRetry");
    try std.testing.expect(c.JS_IsAsyncFunction(function));
    try std.testing.expect(s.equal(try s.get(function, "length"), c.JS_NewInt32(engine.context, 1)));
    c.JS_RunGC(engine.runtime);
    try s.put(try s.own(c.JS_GetGlobalObject(engine.context)), "actualManagementHttp", first);
    const value = try engine.evalModule(@embedFile("../verification/sdk-application-runtime-owner-sourceonly-20261017/observe-management-http.mjs") ++
        \\const observed=await observeManagementHttp(actualManagementHttp.fetchWithRetry);globalThis.actualManagementRows=observed;
        \\const r=observed.rows;if(r.length!==21)throw Error('all original caller inputs required');
        \\if(r[0][1]!==true||r[0][2].length!==3||r[0][2].some(x=>x.some(v=>v!==true)))throw Error('default retry/input/init/receiver');
        \\for(const row of r.filter(x=>x[0]==='status')){const retry=row[1]!==501;if(row[2]!== (retry?2:1)||row[3]!== (retry?1:0)||row[4]!==!retry||row[5]!==retry)throw Error('real status policy')}
        \\const find=name=>r.find(x=>x[0]===name);if(JSON.stringify(find('cancel-await-undefined')[2])!==JSON.stringify(['fetch1','cancel','microtask','fetch2']))throw Error('actual cancel Await');
        \\if(find('cancel-rejection-discarded')[1]!==true||find('cancel-rejection-discarded')[2]!==2)throw Error('cancel catch');
        \\if(find('parent-before-fetch')[1]!==true||find('parent-before-fetch')[2]!==0)throw Error('parent preflight');
        \\const shared=find('shared-timeout');if(shared[1]!==true||shared[2].length!==1||shared[3]!==2||shared[4]!==true)throw Error('overall signal identity');
        \\const attempt=find('attempt-timeout');if(attempt[1]!==true||attempt[2]!==2||attempt[3]!==true)throw Error('attempt signals');
        \\if(r.filter(x=>x[0]==='zero-retry-raw').some(x=>x[1]!==true||x[2]!==true||x[3]!==1))throw Error('raw rejection');
        \\const option=find('option-callee-order');if(option[1]!==true||JSON.stringify(option[2])!==JSON.stringify(['max-read1','get-finite','max-read2',['finite',true,2],'get-max','get-floor','max-read3',['floor',true,3],['max',true,0,3]]))throw Error('live option/callee order');
        \\if(JSON.stringify(find('status-callee-before-argument')[2])!==JSON.stringify(['get-has','status',['selected-has',503]]))throw Error('Set callee capture');
        \\if(find('catch-body-failure')[1]!==true||find('catch-body-failure')[2]!==1)throw Error('failure inside Source catch');
    , "actual-management-http-caller.mjs");
    engine.freeValue(value);
}
test "SDK management HTTP cancellation Await rejected DATA never gains fatal authority" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    try setup(engine);
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const global = try s.own(c.JS_GetGlobalObject(engine.context));
    const namespace = try s.own(try @import("extensions/native_sdk_management_http.zig").create(engine));
    const reason = try s.own(try engine.checked(c.JS_NewError(engine.context)));
    c.JS_SetUncatchableError(engine.context, reason);
    try s.put(global, "ownedManagementReason", reason); try s.put(global, "actualManagementHttp", namespace);
    const value = try engine.evalModule(
        \\const saved=Object.getOwnPropertyDescriptor(globalThis,'fetch');let calls=0;const final={status:200};
        \\try{globalThis.fetch=()=>++calls===1?{status:503,body:{cancel(){return Promise.reject(ownedManagementReason)}}}:final;if(await actualManagementHttp.fetchWithRetry('owned')!==final||calls!==2)throw Error('rejected DATA must enter empty catch')}finally{Object.defineProperty(globalThis,'fetch',saved)}
    , "actual-management-cancel-data.mjs");
    engine.freeValue(value);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(!c.JS_HasException(engine.context));
}
test "SDK management HTTP synchronous retry loop is bounded and missing fetch stays ReferenceError" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    try setup(engine);
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    try s.put(try s.own(c.JS_GetGlobalObject(engine.context)), "actualManagementHttp", try s.own(try @import("extensions/native_sdk_management_http.zig").create(engine)));
    const value = try engine.evalModule(
        \\const saved=Object.getOwnPropertyDescriptor(globalThis,'fetch'),reason={owned:'sync'};let calls=0,caught;
        \\try{globalThis.fetch=()=>{calls++;throw reason};try{await actualManagementHttp.fetchWithRetry('owned',undefined,{maxRetries:128})}catch(e){caught=e}if(caught!==reason||calls!==129)throw Error('structured bounded retry');delete globalThis.fetch;caught=undefined;try{await actualManagementHttp.fetchWithRetry('owned',undefined,{maxRetries:0})}catch(e){caught=e}if(!(caught instanceof ReferenceError))throw Error('missing global binding')}finally{Object.defineProperty(globalThis,'fetch',saved)}
    , "actual-management-sync-loop.mjs");
    engine.freeValue(value);
}
test "SDK management HTTP native owner requires truthful profile and real resource owners" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const missing = c.pi_js_undefined();
    try std.testing.expectError(error.RequiredTruthfulNativeSdkRuntimeProfile, @import("extensions/native_sdk_application_bootstrap.zig").createNativeFromOwners(engine, .{
        .process = missing, .os = missing, .url = missing, .child_process = missing, .config_module_url = missing, .user_agent_runtime = .source,
    }, .{ .package_manager = missing, .chalk_default = missing, .load_extension_from_factory = missing, .load_extensions_cached = missing }));
    try std.testing.expectError(error.RequiredActualResourceLoaderOwners, @import("extensions/native_sdk_application_bootstrap.zig").createNativeFromOwners(engine, .{
        .process = missing, .os = missing, .url = missing, .child_process = missing, .config_module_url = missing, .user_agent_runtime = .native_zig,
    }, .{ .package_manager = missing, .chalk_default = missing, .load_extension_from_factory = missing, .load_extensions_cached = missing }));
    try std.testing.expect(!engine.native_module_values.contains("pi-native:sdk-runtime-imports-native-zig"));
    try std.testing.expect(!engine.native_module_values.contains("pi-private:sdk-management-http"));
}

var management_fault_allocator: ?*std.testing.FailingAllocator = null;
var management_fault_calls: usize = 0;
fn failAtActualFetch(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    management_fault_calls += 1;
    const allocator = management_fault_allocator.?;
    allocator.fail_index = allocator.alloc_index;
    defer allocator.fail_index = std.math.maxInt(usize);
    const bytes = try engine.gpa.alloc(u8, 1);
    defer engine.gpa.free(bytes);
    return c.pi_js_undefined();
}

test "SDK management HTTP real native fetch allocation failure bypasses retry and guest catch" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try em.Engine.init(failing.allocator(), .{}); defer engine.deinit();
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const root = try s.own(c.JS_GetGlobalObject(engine.context));
    try s.put(root, "actualManagementHttp", try s.own(try @import("extensions/native_sdk_management_http.zig").create(engine)));
    try s.put(root, "fetch", try s.own(try @import("extensions/native_node_function.zig").createArrow(engine, "fetch", 1, failAtActualFetch, &.{})));
    const guest = try s.own(try engine.eval("globalThis.managementCaught=0;(async()=>{try{await actualManagementHttp.fetchWithRetry('owned')}catch(error){managementCaught++}})", "actual-management-gpa-catch.js", c.JS_EVAL_TYPE_GLOBAL));
    management_fault_allocator = &failing;
    management_fault_calls = 0;
    defer management_fault_allocator = null;
    const result = c.JS_Call(engine.context, guest, c.pi_js_undefined(), 0, null); defer engine.freeValue(result);
    try std.testing.expect(failing.has_induced_failure and c.JS_IsException(result));
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.native_allocation_exception.?));
    try std.testing.expectEqual(@as(usize, 1), management_fault_calls);
    try std.testing.expect(s.equal(try s.global("managementCaught"), c.JS_NewInt32(engine.context, 0)));
    try std.testing.expect(engine.native_fatal_invocation == null);
}

test "SDK management HTTP signal spread preserves own keys getters and preflight outside try" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    try setup(engine);
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    try s.put(try s.own(c.JS_GetGlobalObject(engine.context)), "actualManagementHttp", try s.own(try @import("extensions/native_sdk_management_http.zig").create(engine)));
    const value = try engine.evalModule(
        \\const saved=Object.getOwnPropertyDescriptor(globalThis,'fetch'),symbol=Symbol('owned'),signal=new AbortController().signal,log=[];let calls=0;
        \\try{const target={get signal(){log.push('signal');return signal},get headers(){log.push('headers');return{owned:true}},[symbol]:'symbol'};Object.defineProperty(target,'hidden',{value:1});const init=new Proxy(target,{ownKeys(o){log.push('keys');return Reflect.ownKeys(o)},getOwnPropertyDescriptor(o,k){log.push(['descriptor',typeof k==='symbol'?'symbol':k]);return Reflect.getOwnPropertyDescriptor(o,k)}});globalThis.fetch=function(input,options){calls++;if(input!=='owned'||this!==undefined||options===init||options.signal!==signal||options[symbol]!=='symbol'||'hidden'in options||!options.headers.owned)throw Error('spread contents');return{status:200}};await actualManagementHttp.fetchWithRetry('owned',init);if(calls!==1||JSON.stringify(log)!==JSON.stringify(['signal','keys',['descriptor','signal'],'signal',['descriptor','headers'],'headers',['descriptor','hidden'],['descriptor','symbol']]))throw Error('spread descriptor/getter order');
        \\const reason={owned:'preflight-getter'};calls=0;const preflight={get throwIfAborted(){throw reason}};let caught;try{await actualManagementHttp.fetchWithRetry('owned',{signal:preflight})}catch(e){caught=e}if(caught!==reason||calls!==0)throw Error('preflight must not retry');}finally{Object.defineProperty(globalThis,'fetch',saved)}
    , "actual-management-spread-preflight.mjs");
    engine.freeValue(value);
}

const CleanupEmission = struct { engine: *em.Engine, reason: c.JSValue, finalizers: usize = 0, quiet: bool = false };
var cleanup_selected_function: ?c.JSValue = null;
var cleanup_selected_calls: usize = 0;
fn emitCleanup(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const owner: *CleanupEmission = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
    owner.finalizers += 1;
    if (owner.quiet) return;
    _ = c.JS_Throw(owner.engine.context, c.JS_DupValue(owner.engine.context, owner.reason));
}
fn cleanupToken(owner: *CleanupEmission) !c.JSValue {
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(owner.engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Owned management cleanup", .finalizer = emitCleanup };
    if (c.JS_NewClass(owner.engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const value = try owner.engine.checked(c.JS_NewObjectClass(owner.engine.context, class));
    _ = c.JS_SetOpaque(value, owner);
    return value;
}
fn selectedHas(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    cleanup_selected_calls += 1;
    return c.pi_js_undefined();
}
fn takeSelectedHas(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const value = cleanup_selected_function orelse return error.RequiredSoleOwnedManagementFunction;
    cleanup_selected_function = null; // Transfer sole function ownership to VM.
    return value;
}
test "SDK management HTTP Source throw survives ordinary sole-holder cleanup while actual fatal promotes" {
    for ([_]bool{ false, true }) |fatal_cleanup| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        var s: Scope = .{ .engine = engine }; defer s.deinit();
        const root = try s.own(c.JS_GetGlobalObject(engine.context));
        try s.put(root, "actualManagementHttp", try s.own(try @import("extensions/native_sdk_management_http.zig").create(engine)));
        const original = try s.own(try engine.checked(c.JS_NewError(engine.context)));
        const cleanup = try s.own(try engine.checked(c.JS_NewError(engine.context)));
        if (fatal_cleanup) c.JS_SetUncatchableError(engine.context, cleanup);
        try s.put(root, "ownedManagementOriginal", original);
        var emission: CleanupEmission = .{ .engine = engine, .reason = cleanup };
        const token = try cleanupToken(&emission);
        cleanup_selected_function = @import("extensions/native_node_function.zig").createArrow(engine, "selectedHas", 1, selectedHas, &.{token}) catch |err| { engine.freeValue(token); return err; };
        engine.freeValue(token); // Only the transferred function retains token.
        defer { if (cleanup_selected_function) |value| engine.freeValue(value); cleanup_selected_function = null; }
        cleanup_selected_calls = 0;
        const prototype = try s.get(try s.global("Set"), "prototype");
        const atom = c.JS_NewAtom(engine.context, "has"); defer c.JS_FreeAtom(engine.context, atom);
        const getter = try @import("extensions/native_node_function.zig").createArrow(engine, "get has", 0, takeSelectedHas, &.{});
        if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return @import("extensions/native_js_values.zig").capture(engine);
        const source =
            \\globalThis.managementSeen=undefined;globalThis.fetch=()=>({get status(){throw ownedManagementOriginal}});try{await actualManagementHttp.fetchWithRetry('owned',undefined,{maxRetries:0})}catch(reason){globalThis.managementSeen=reason}
        ;
        if (fatal_cleanup) {
            try std.testing.expectError(error.JavaScriptException, engine.evalModule(source, "actual-management-fatal-cleanup.mjs"));
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, cleanup, engine.captured_exception orelse return error.RequiredActualCleanupFatal));
            try std.testing.expect(c.JS_IsUndefined(try s.global("managementSeen")));
        } else {
            const result = try engine.evalModule(source, "actual-management-ordinary-cleanup.mjs"); engine.freeValue(result);
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, try s.global("managementSeen")));
        }
        try std.testing.expectEqual(@as(usize, 1), emission.finalizers);
        try std.testing.expectEqual(@as(usize, 0), cleanup_selected_calls);
        try std.testing.expect(cleanup_selected_function == null);
    }
}

/// Prepared actual-owner entry, not a fake positive graph/test declaration.
/// The caller must first supply the real child/config/resource bindings.
pub fn verifyNativeOwnerGetterBoundary(engine: *em.Engine, runtime: @import("extensions/native_sdk_runtime_imports.zig").Inputs, resources: @import("extensions/native_sdk_application_bootstrap.zig").ResourceImports) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const actual = try s.own(try @import("extensions/native_sdk_runtime_imports.zig").create(engine, runtime));
    const prototype = try s.get(try s.get(try s.get(actual, "authStorage"), "AuthStorage"), "prototype");
    const original = try s.get(prototype, "reloadFromStorageAsync");
    const root = try s.own(c.JS_GetGlobalObject(engine.context));
    const reason = try s.own(try engine.eval("globalThis.ownerDiagnosticReads=0;({toString(){ownerDiagnosticReads++;return'forbidden owner diagnostic'}})", "actual-owner-raw-reason.js", c.JS_EVAL_TYPE_GLOBAL));
    try s.put(root, "actualOwnerRawReason", reason);
    const getter = try s.own(try engine.eval("(()=>{throw actualOwnerRawReason})", "actual-owner-auth-getter.js", c.JS_EVAL_TYPE_GLOBAL));
    const atom = c.JS_NewAtom(engine.context, "reloadFromStorageAsync"); defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, c.JS_DupValue(engine.context, getter), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return @import("extensions/native_js_values.zig").capture(engine);
    defer { _ = c.JS_DefinePropertyValueStr(engine.context, prototype, "reloadFromStorageAsync", c.JS_DupValue(engine.context, original), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE); }
    const suppression = engine.native_exception_diagnostics_suppressed;
    try std.testing.expectError(error.JavaScriptException, @import("extensions/native_sdk_application_bootstrap.zig").createNativeFromOwners(engine, runtime, resources));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.captured_exception orelse return error.RequiredActualOwnerGetterReason));
    try std.testing.expect(s.equal(try s.global("ownerDiagnosticReads"), c.JS_NewInt32(engine.context, 0)));
    try std.testing.expectEqual(suppression, engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "SDK management HTTP native owner pending entry wins before validation and GPA" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try em.Engine.init(failing.allocator(), .{}); defer engine.deinit();
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const original = try s.own(try engine.checked(c.JS_NewError(engine.context)));
    c.JS_SetUncatchableError(engine.context, original);
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, original));
    const missing = c.pi_js_undefined();
    failing.fail_index = failing.alloc_index;
    const result = @import("extensions/native_sdk_application_bootstrap.zig").createNativeFromOwners(engine, .{
        .process = missing, .os = missing, .url = missing, .child_process = missing, .config_module_url = missing, .user_agent_runtime = .source,
    }, .{ .package_manager = missing, .chalk_default = missing, .load_extension_from_factory = missing, .load_extensions_cached = missing });
    failing.fail_index = std.math.maxInt(usize);
    try std.testing.expectError(error.JavaScriptException, result);
    try std.testing.expect(!failing.has_induced_failure);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, engine.captured_exception orelse return error.RequiredOriginalEntryReason));
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
var maximum_holder: ?c.JSValue = null;
var maximum_reads: usize = 0;
var maximum_lifetime: ?*CleanupEmission = null;
var maximum_observed_retirement: bool = false;
fn takeMaximum(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    maximum_reads += 1;
    if (maximum_reads == 1) {
        const value = maximum_holder orelse return error.RequiredMaximumHolder;
        maximum_holder = null;
        return value;
    }
    return c.JS_NewInt32(engine.context, 0);
}
fn observeMaximum(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    maximum_observed_retirement = maximum_lifetime.?.finalizers == 1;
    return c.pi_js_undefined();
}
test "SDK management HTTP default expression temporaries retire before later signal getter" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const root = try s.own(c.JS_GetGlobalObject(engine.context));
    try s.put(root, "actualManagementHttp", try s.own(try @import("extensions/native_sdk_management_http.zig").create(engine)));
    var emission: CleanupEmission = .{ .engine = engine, .reason = c.pi_js_undefined(), .quiet = true };
    maximum_holder = try cleanupToken(&emission);
    maximum_reads = 0; maximum_lifetime = &emission; maximum_observed_retirement = false;
    defer { if (maximum_holder) |value| engine.freeValue(value); maximum_holder = null; maximum_lifetime = null; }
    const options = try s.object(); const initial = try s.object();
    const max_atom = c.JS_NewAtom(engine.context, "maxRetries"); defer c.JS_FreeAtom(engine.context, max_atom);
    const signal_atom = c.JS_NewAtom(engine.context, "signal"); defer c.JS_FreeAtom(engine.context, signal_atom);
    const max_getter = try @import("extensions/native_node_function.zig").createArrow(engine, "get maxRetries", 0, takeMaximum, &.{});
    if (c.JS_DefinePropertyGetSet(engine.context, options, max_atom, max_getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return @import("extensions/native_js_values.zig").capture(engine);
    const signal_getter = try @import("extensions/native_node_function.zig").createArrow(engine, "get signal", 0, observeMaximum, &.{});
    if (c.JS_DefinePropertyGetSet(engine.context, initial, signal_atom, signal_getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return @import("extensions/native_js_values.zig").capture(engine);
    try s.put(root, "actualLifetimeOptions", options); try s.put(root, "actualLifetimeInit", initial);
    const result = try engine.evalModule(
        \\globalThis.fetch=()=>({status:200});if((await actualManagementHttp.fetchWithRetry('owned',actualLifetimeInit,actualLifetimeOptions)).status!==200)throw Error('actual lifetime response');
    , "actual-management-option-lifetime.mjs");
    engine.freeValue(result);
    try std.testing.expectEqual(@as(usize, 3), maximum_reads);
    try std.testing.expectEqual(@as(usize, 1), emission.finalizers);
    try std.testing.expect(maximum_observed_retirement and maximum_holder == null);
}
var descriptor_holder: ?c.JSValue = null;
fn takeDescriptorHolder(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const value = descriptor_holder orelse return error.RequiredSoleDescriptorHolder;
    descriptor_holder = null;
    return value;
}
test "SDK management HTTP actual Proxy descriptor retirement preserves Source reason or fatal promotion" {
    for ([_]bool{ false, true }) |fatal_cleanup| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        try setup(engine);
        var s: Scope = .{ .engine = engine }; defer s.deinit();
        const root = try s.own(c.JS_GetGlobalObject(engine.context));
        try s.put(root, "actualManagementHttp", try s.own(try @import("extensions/native_sdk_management_http.zig").create(engine)));
        const original = try s.own(try engine.checked(c.JS_NewError(engine.context)));
        const cleanup = try s.own(try engine.checked(c.JS_NewError(engine.context)));
        if (fatal_cleanup) c.JS_SetUncatchableError(engine.context, cleanup);
        try s.put(root, "ownedDescriptorOriginal", original);
        var emission: CleanupEmission = .{ .engine = engine, .reason = cleanup };
        descriptor_holder = try cleanupToken(&emission);
        defer { if (descriptor_holder) |value| engine.freeValue(value); descriptor_holder = null; }
        try s.put(root, "takeOwnedDescriptorHolder", try s.own(try @import("extensions/native_node_function.zig").createArrow(engine, "takeOwnedDescriptorHolder", 0, takeDescriptorHolder, &.{})));
        const source =
            \\globalThis.descriptorSeen=undefined;globalThis.descriptorFetchCalls=0;globalThis.fetch=()=>{descriptorFetchCalls++;return{status:200}};const signal=new AbortController().signal;const init=new Proxy({},{ownKeys(){return['owned']},getOwnPropertyDescriptor(){return{value:takeOwnedDescriptorHolder(),enumerable:true,configurable:true,writable:true}},get(target,key){if(key==='signal')return signal;throw ownedDescriptorOriginal}});try{await actualManagementHttp.fetchWithRetry('owned',init,{maxRetries:0})}catch(reason){globalThis.descriptorSeen=reason}
        ;
        if (fatal_cleanup) {
            try std.testing.expectError(error.JavaScriptException, engine.evalModule(source, "actual-management-descriptor-fatal.mjs"));
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, cleanup, engine.captured_exception orelse return error.RequiredDescriptorFatal));
            try std.testing.expect(c.JS_IsUndefined(try s.global("descriptorSeen")));
        } else {
            const value = try engine.evalModule(source, "actual-management-descriptor-ordinary.mjs"); engine.freeValue(value);
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, try s.global("descriptorSeen")));
        }
        try std.testing.expect(s.equal(try s.global("descriptorFetchCalls"), c.JS_NewInt32(engine.context, 0)));
        try std.testing.expectEqual(@as(usize, 1), emission.finalizers);
        try std.testing.expect(descriptor_holder == null);
    }
}
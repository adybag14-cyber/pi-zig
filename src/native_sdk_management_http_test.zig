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

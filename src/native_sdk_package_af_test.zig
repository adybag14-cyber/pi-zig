//! Prepared actual package class fragments, not a published full package graph.
//! External package/transport dependencies are neither substituted nor selected.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
fn actualFragment(engine: *em.Engine, scope: *Scope) !c.JSValue {
    const paths = engine.native_module_values.get("node:path") orelse return error.RequiredActualPaths;
    const filesystem = engine.native_module_values.get("node:fs") orelse return error.RequiredActualFilesystem;
    const prototype = try scope.object();
    try @import("extensions/native_sdk_package_manager.zig").installProgress(engine, prototype);
    try @import("extensions/native_sdk_package_settings.zig").install(engine, prototype, .{ .exists_sync = try scope.get(filesystem, "existsSync"), .relative = try scope.get(paths, "relative") });
    try @import("extensions/native_sdk_package_commands.zig").install(engine, prototype, .{ .basename = try scope.get(paths, "basename"), .exists_sync = try scope.get(filesystem, "existsSync") });
    const constructor = try scope.own(try @import("extensions/native_sdk_package_manager.zig").constructor(engine, prototype));
    const managers = try scope.own(try @import("extensions/native_sdk.zig").managerImports(engine));
    const api = try scope.object();
    try scope.put(api, "DefaultPackageManager", constructor);
    try scope.put(api, "SettingsManager", try scope.get(managers, "SettingsManager"));
    try scope.put(api, "physicalRoot", try scope.invoke(try scope.global("process"), "cwd", &.{}));
    return api;
}
fn setup(engine: *em.Engine, environment: *const std.process.Environ.Map) !void {
    try @import("extensions/native_sdk_application_bootstrap.zig").installPlatform(engine, std.testing.io, environment, &.{"actual-package-af-fragment"});
}
test "SDK package AF real progress body original caller and native class identity" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try setup(engine, &environment);
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const api = try actualFragment(engine, &s);
    try s.put(try s.own(c.JS_GetGlobalObject(engine.context)), "actualPackageFragment", api);
    const prototype = try s.get(try s.get(api, "DefaultPackageManager"), "prototype");
    inline for (.{ "withProgress", "runNpmCommand", "installNpm", "uninstallNpm", "installNpmBatch" }) |name| try std.testing.expect(c.JS_IsAsyncFunction(try s.get(prototype, name)));
    c.JS_RunGC(engine.runtime);
    const result = try engine.evalModule(@embedFile("../verification/sdk-package-af-sourceonly-20261017/observe-package-progress.mjs") ++
        \\const rows=(await observePackageProgress(actualPackageFragment)).rows;if(rows.length!==11)throw Error('all original progress inputs');
        \\const find=name=>rows.find(r=>r[0]===name);const success=find('success');if(success[1]||success[4]!==1||JSON.stringify(success[5].map(r=>r[0]))!==JSON.stringify(['start','operation','complete']))throw Error('actual progress success');
        \\for(const name of ['operation-sync','operation-await','complete','start','error-callback']){const row=find(name);if(!row[1]||!row[2]||row[4]!== (name==='start'?0:1))throw Error('raw progress throw');if(name==='start'&&row[5].length!==1)throw Error('start outside try');}
        \\for(const name of ['message-getter','string-conversion','instanceof-getter','error-callee'])if(find(name)[1]!==true)throw Error('catch body replacement');
        \\const awaited=find('actual-await');if(!awaited[1]||JSON.stringify(awaited[2])!==JSON.stringify(['start','caller','microtask','complete']))throw Error('genuine operation Await');
    , "actual-package-progress-caller.mjs");
    engine.freeValue(result);
}
test "SDK package AF rejected marked and fresh private DATA reaches progress error unchanged" {
    for ([_]bool{ false, true }) |private_tag| {
        var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        try setup(engine, &environment);
        var s: Scope = .{ .engine = engine }; defer s.deinit();
        const root = try s.own(c.JS_GetGlobalObject(engine.context));
        try s.put(root, "actualPackageFragment", try actualFragment(engine, &s));
        // Start the real AF before the private reason is born. This is DATA
        // produced while an unrelated operation is suspended, not a new throw.
        const pending = try s.own(try engine.eval(
            \\(async()=>{const{DefaultPackageManager,SettingsManager,physicalRoot}=actualPackageFragment;const manager=new DefaultPackageManager({cwd:physicalRoot,agentDir:physicalRoot,settingsManager:SettingsManager.inMemory()}),events=[];manager.setProgressCallback(e=>events.push(e.type));const waiting=new Promise((resolve,reject)=>{globalThis.actualPackageReject=reject});let actual;try{await manager.withProgress('update','owned','Preparing',()=>waiting)}catch(reason){actual=reason}if(actual!==actualPackageReason||events.join()!=='start,error')throw Error('settled DATA progress catch')})()
        , "actual-package-progress-start.js", c.JS_EVAL_TYPE_GLOBAL));
        const reason = if (private_tag) blk: {
            try std.testing.expectError(error.JavaScriptException, engine.checked(engine.throwNativeOutOfMemory()));
            const captured = engine.captured_exception orelse return error.RequiredActualPrivateReason;
            engine.captured_exception = null;
            break :blk try s.own(captured);
        } else try s.own(try engine.checked(c.JS_NewError(engine.context)));
        c.JS_SetUncatchableError(engine.context, reason);
        try std.testing.expect(c.JS_IsUncatchableError(reason));
        try s.put(root, "actualPackageReason", reason);
        const rejected = try s.call(try s.global("actualPackageReject"), c.pi_js_undefined(), &.{reason});
        _ = rejected;
        const finished = try engine.awaitValue(pending);
        engine.freeValue(finished);
        try std.testing.expect(c.JS_IsUncatchableError(reason));
        try std.testing.expect(!c.JS_HasException(engine.context));
    }
}
test "SDK package AF actual npm command preserves live lookup argument receiver and awaited void" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try setup(engine, &environment);
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    try s.put(try s.own(c.JS_GetGlobalObject(engine.context)), "actualPackageFragment", try actualFragment(engine, &s));
    const value = try engine.evalModule(
        \\const{DefaultPackageManager,SettingsManager,physicalRoot}=actualPackageFragment;const manager=new DefaultPackageManager({cwd:physicalRoot,agentDir:physicalRoot,settingsManager:SettingsManager.inMemory()}),log=[],options={owned:true};
        \\Object.defineProperty(manager,'getNpmCommand',{get(){log.push('get-command');return function(){log.push(['command-receiver',this===manager]);return{get command(){log.push('command-name');return'owned'},get args(){log.push('command-args');return['prefix']}}}});
        \\Object.defineProperty(manager,'runCommand',{get(){log.push('get-run');return function(command,args,opts){log.push(['run',this===manager,command,args.join(),opts===options]);return Promise.resolve('ignored')}}});
        \\const pending=manager.runNpmCommand(['argument'],options);log.push('caller');if(await pending!==undefined||JSON.stringify(log)!==JSON.stringify(['get-command',['command-receiver',true],'get-run','command-name','command-args',['run',true,'owned','prefix,argument',true],'caller']))throw Error('actual npm command order');
    , "actual-package-npm-command-chain.mjs");
    engine.freeValue(value);
}
test "SDK package AF rejection guard ignores DATA tags but preserves actual pending first" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const data = try s.own(try engine.checked(c.JS_NewError(engine.context)));
    c.JS_SetUncatchableError(engine.context, data);
    try @import("extensions/native_sdk_package_catch.zig").guard(engine, data, 0);
    try std.testing.expect(c.JS_IsUncatchableError(data));
    const actual = try s.own(try engine.checked(c.JS_NewError(engine.context)));
    c.JS_SetUncatchableError(engine.context, actual);
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, actual));
    try std.testing.expectError(error.JavaScriptException, @import("extensions/native_sdk_package_catch.zig").guard(engine, data, 0));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, engine.captured_exception orelse return error.RequiredActualPendingEvent));
}
var progress_fault_allocator: ?*std.testing.FailingAllocator = null;
var progress_fault_calls: usize = 0;
fn failProgressAllocation(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    progress_fault_calls += 1;
    const allocator = progress_fault_allocator.?;
    allocator.fail_index = allocator.alloc_index;
    defer allocator.fail_index = std.math.maxInt(usize);
    const bytes = try engine.gpa.alloc(u8, 1); defer engine.gpa.free(bytes);
    return c.pi_js_undefined();
}
test "SDK package AF actual completion callback GPA failure bypasses error notification and guest catch" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var environment: std.process.Environ.Map = .init(failing.allocator()); defer environment.deinit();
    const engine = try em.Engine.init(failing.allocator(), .{}); defer engine.deinit();
    try setup(engine, &environment);
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const root = try s.own(c.JS_GetGlobalObject(engine.context));
    try s.put(root, "actualPackageFragment", try actualFragment(engine, &s));
    try s.put(root, "ownedPackageFault", try s.own(try @import("extensions/native_node_function.zig").createArrow(engine, "ownedPackageFault", 0, failProgressAllocation, &.{})));
    progress_fault_allocator = &failing; progress_fault_calls = 0;
    defer progress_fault_allocator = null;
    try std.testing.expectError(error.JavaScriptException, engine.evalModule(
        \\const{DefaultPackageManager,SettingsManager,physicalRoot}=actualPackageFragment,manager=new DefaultPackageManager({cwd:physicalRoot,agentDir:physicalRoot,settingsManager:SettingsManager.inMemory()});globalThis.packageEvents=[];globalThis.packageCaught=0;manager.setProgressCallback(event=>{packageEvents.push(event.type);if(event.type==='complete')ownedPackageFault()});try{await manager.withProgress('update','owned','Preparing',()=>Promise.resolve())}catch(error){packageCaught++}
    , "actual-package-progress-gpa.mjs"));
    try std.testing.expect(failing.has_induced_failure);
    const reason = engine.captured_exception orelse return error.RequiredActualProgressFatal;
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.native_allocation_exception.?));
    try std.testing.expectEqual(@as(usize, 1), progress_fault_calls);
    try std.testing.expect(s.equal(try s.global("packageCaught"), c.JS_NewInt32(engine.context, 0)));
    try std.testing.expect(s.equal(try s.invoke(try s.global("packageEvents"), "join", &.{try s.text(",")}), try s.text("start,complete")));
    try std.testing.expect(engine.native_fatal_invocation == null);
}
//! Actual public ModelsImpl refresh/publication qualification against Source60.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;

fn clone(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return @import("extensions/native_structured_clone.zig").clone(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn install(engine: *em.Engine) !void {
    engine.native_io = std.testing.io;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const namespace = try @import("extensions/native_ai_models_namespace.zig").create(engine);
    defer engine.freeValue(namespace);
    const core = engine.native_models_core_namespace.?;
    const api = try sdk.object(engine);
    defer engine.freeValue(api);
    inline for (.{ "createModels", "ModelsError" }) |name| try sdk.put(engine, api, name, try sdk.get(engine, namespace, name));
    // The store is the actual shared class, exported from its original module.
    try sdk.put(engine, api, "InMemoryModelsStore", try sdk.get(engine, core, "InMemoryModelsStore"));
    try sdk.put(engine, global, "modelsRefreshAPI", c.JS_DupValue(engine.context, api));
    try sdk.put(engine, global, "structuredClone", try engine.checked(c.JS_NewCFunction(engine.context, clone, "structuredClone", 1)));
}

test "native actual Models refresh compares all genuine4954 Source60 observations" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const expected = @embedFile("extensions/fixtures/ai-models-refresh-4954.json");
    const terminated = try engine.gpa.dupeZ(u8, expected);
    defer engine.gpa.free(terminated);
    try sdk.put(engine, global, "modelsRefreshExpected", try engine.checked(c.JS_ParseJSON(engine.context, terminated.ptr, expected.len, "original4954-models-refresh.json")));
    const compared = engine.evalModule(@embedFile("extensions/fixtures/ai-models-refresh-4954.input.txt") ++
        \\if(modelsRefreshExpected.sourceHead!=='4954d760504c11df9b2cbdc040346107b6a8153d'||modelsRefreshExpected.runtime!=='v24.14.0'||modelsRefreshExpected.count!==60||modelsRefreshExpected.rows.length!==60||modelsRefreshRows.length!==60)throw Error('Actual Source60 inventory required');
        \\for(let i=0;i<modelsRefreshRows.length;i++)if(JSON.stringify(modelsRefreshRows[i])!==JSON.stringify(modelsRefreshExpected.rows[i]))throw Error(JSON.stringify({case:i,actual:modelsRefreshRows[i],source:modelsRefreshExpected.rows[i]}));
    , "native-actual-models-refresh-source60.mjs") catch |err| {
        std.debug.print("Actual Models refresh Source60: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(compared);
    c.JS_RunGC(engine.runtime);
    std.debug.print("NATIVE_ACTUAL_MODELS_REFRESH_SOURCE_CASES=60\n", .{});
}

test "native actual Models publication retains queued work through collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const prepared = try engine.evalModule(
        \\const m=modelsRefreshAPI.createModels({credentials:{read:async()=>undefined},modelsStore:{write(id,entry){globalThis.refreshRetainedEntry=entry;return new Promise(resolve=>{globalThis.refreshRelease=resolve})}},authContext:{env:()=>undefined,fileExists:()=>false}});
        \\const s=m.beginProviderRefresh('p'),entry={models:[],date:new Date(42)};entry.self=entry;
        \\globalThis.refreshRetained=m.publishProviderModels('p',s.generation,s.controller.signal,{persist:entry,update(){globalThis.refreshUpdateRetained=true}});
        \\for(let i=0;i<16;i++)await Promise.resolve();if(!refreshRelease)throw Error('publication not started');delete globalThis.modelsRefreshAPI;
    , "models-refresh-retain-before-gc.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\if(refreshRetainedEntry.self!==refreshRetainedEntry||refreshRetainedEntry.date.getTime()!==42)throw Error('clone graph lost');refreshRelease();
        \\if(await refreshRetained!==true||!refreshUpdateRetained)throw Error('queued publication roots lost');
        \\delete globalThis.refreshRetainedEntry;delete globalThis.refreshRelease;delete globalThis.refreshRetained;delete globalThis.refreshUpdateRetained;
    , "models-refresh-retain-after-gc.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}

test "native actual Models refresh releases every failed host allocation without swallowed failures" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            var progress: em.ProgressProbe = .{};
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            engine.progress_probe = &progress;
            defer engine.deinit();
            try install(engine);
            const generation = engine.native_allocation_generation;
            const module = engine.evalModule(
                \\const {createModels,InMemoryModelsStore}=modelsRefreshAPI;const store=new InMemoryModelsStore();
                \\const m=createModels({credentials:{async read(){return {type:'api_key',key:'owned'}}},modelsStore:store,authContext:{env:()=>undefined,fileExists:()=>false}});
                \\const p={id:'p',auth:{apiKey:{async resolve({credential}){return {auth:{apiKey:credential.key},env:{OWNED:'yes'}}}}},getModels(){return []},async refreshModels(c){if(c.allowNetwork){const entry={models:[{id:'owned'}]};entry.self=entry;if(!await c.publish({persist:entry,update(){globalThis.refreshAllocationUpdated=true}}))throw Error('publication rejected')}}};
                \\m.setProvider(p);const r=await m.refresh({force:true});if(r.aborted||r.errors.size||!globalThis.refreshAllocationUpdated||m.refreshControllers.size)throw Error('refresh failed');
                \\const entry=await store.read('p');if(entry.self!==entry||entry.models[0].id!=='owned')throw Error('persistence failed');
                \\m.setProvider({id:'failed',getModels(){return []},async refreshModels(){throw {ordinary:true}}});const failed=await m.refresh({providers:['failed'],allowNetwork:false});if(failed.errors.get('failed')?.code!=='model_source')throw Error('source failure catch failed');
                \\delete globalThis.refreshAllocationUpdated;export const proof=true;
            , "models-refresh-owned-allocations.mjs") catch |err| {
                const classified = engine.nativeAllocationError(err, generation);
                if (classified != error.OutOfMemory) {
                    const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                    const captured_tag = if (engine.captured_exception) |reason| c.pi_js_native_allocation_error_generation(reason) else 0;
                    const retained_tag = if (engine.native_allocation_exception) |reason| c.pi_js_native_allocation_error_generation(reason) else 0;
                    std.debug.print("MODELS_REFRESH_ALLOCATION_FAILURE fail_index={d} alloc_index={d} induced={any} error={s} boundary={d} current={d} captured_tag={d} retained_tag={d} pending_jobs={any} job_attempts={d} empty_polls={d}\n", .{ failing.fail_index, failing.alloc_index, failing.has_induced_failure, @errorName(classified), generation, engine.native_allocation_generation, captured_tag, retained_tag, c.JS_IsJobPending(engine.runtime), progress.job_attempts, progress.empty_job_polls });
                    const allocation_stack = failing.getStackTrace();
                    std.debug.dumpStackTrace(&allocation_stack);
                }
                return classified;
            };
            engine.freeValue(module);
            c.JS_RunGC(engine.runtime);
            const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
            if (!failing.has_induced_failure) std.debug.print("NATIVE_ACTUAL_MODELS_REFRESH_HOST_ALLOCATION_POSITIONS={d}\n", .{failing.alloc_index});
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}

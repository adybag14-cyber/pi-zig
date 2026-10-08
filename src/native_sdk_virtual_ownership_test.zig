const std = @import("std");
const sdk = @import("extensions/native_sdk.zig");
const engine_mod = @import("extensions/engine.zig");
const c = engine_mod.c;

test "SDK virtual catalog routing filtering stream and teardown release every failed host allocation" {
    const Probe = struct {
        fn exercise(gpa: std.mem.Allocator) !void {
            const engine = try engine_mod.Engine.init(gpa, .{});
            defer engine.deinit();
            try @import("extensions/native_stream.zig").install(engine);
            const exports = try sdk.object(engine);
            defer engine.freeValue(exports);
            try sdk.install(engine, exports);
            try engine.registerValueModule("virtual-sdk", exports);
            const evaluation = try engine.evalModule(
                \\import {ModelRuntime,createAgentSession,SessionManager,SettingsManager,DefaultResourceLoader} from 'virtual-sdk';import {createAssistantMessageEventStream} from 'pi-ai';
                \\const r=await ModelRuntime.create({modelsPath:null,refreshOnCreate:false,credentials:{read:async()=>undefined,list:async()=>[]}}),m={id:'m',provider:'p',api:'fixture',reasoning:true,thinkingLevelMap:{medium:null,high:'high'},maxTokens:8};
                \\r.registerNativeProvider({id:'p',auth:{apiKey:{check:async()=>({type:'api_key'}),resolve:async()=>({auth:{apiKey:'key'},source:'fixture'})}},getModels:()=>[m],filterModels:()=>[],streamSimple(model,context,options){if(model!==m||options.apiKey!=='key'||(options.maxTokens!==undefined&&options.maxTokens!==8))throw Error('physical request');const stream=createAssistantMessageEventStream();stream.push({type:'done',message:{role:'assistant',content:[],stopReason:'stop'}});stream.end();return stream}});await r.refresh({allowNetwork:false});
                \\let called=0;const definition={provider:'v',id:'v',name:'Virtual',route(request){if(this!==definition)throw Error('receiver');called++;return {model:m,thinkingLevel:'medium',state:{count:called}}}};r.registerVirtualModel(definition);if(!r.hasConfiguredAuth('v'))throw Error('provisional');const v=r.getModel('v','v'),route=await r.resolveModel(v,[],{reason:'direct',thinkingLevel:'off'});if(route.model!==m||route.thinkingLevel!=='high')throw Error('route');const stream=r.streamSimple(v,{messages:[]},{maxTokens:16,apiKey:'wrong-vendor'});if(called!==1)throw Error('lazy');await stream.result();for await(const event of stream){};r.unregisterVirtualModel('v','v');await r.refresh({allowNetwork:false});if(r.getModel('v','v')!==undefined)throw Error('retirement');
                \\r.registerVirtualModel(definition);const loader=new DefaultResourceLoader({noExtensions:true,noSkills:true,noPromptTemplates:true,noThemes:true,noContextFiles:true,systemPromptOverride:()=>''});await loader.reload();const manager=SessionManager.inMemory();const {session}=await createAgentSession({model:r.getModel('v','v'),modelRuntime:r,sessionManager:manager,settingsManager:SettingsManager.inMemory(),resourceLoader:loader,tools:[]});let states=0;session.subscribe(event=>{if(event.type==='entry_appended'&&event.entry.customType==='pi.virtual-model-state')states++});await session.prompt('one');await session.prompt('two');if(session.model.id!=='v'||states!==2||manager.getBranch().filter(e=>e.type==='custom'&&e.customType==='pi.virtual-model-state').length!==2)throw Error('session projection');session.dispose();
            , "virtual-sdk-allocations.mjs");
            defer engine.freeValue(evaluation);
            const settled = try engine.awaitValue(evaluation);
            defer engine.freeValue(settled);
            c.JS_RunGC(engine.runtime);
        }
        fn run(gpa: std.mem.Allocator) !void {
            const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
            exercise(gpa) catch |err| {
                if (failing.has_induced_failure and (err == error.OutOfMemory or err == error.JavaScriptException)) return error.OutOfMemory;
                std.debug.print("SDK virtual host allocation failure: {s}; induced={any}; index={d}\n", .{ @errorName(err), failing.has_induced_failure, failing.alloc_index });
                return err;
            };
            // Registration starts an observed best-effort background refresh.
            // It may absorb OOM while the public operation succeeds. The
            // allocator still checks complete owner teardown for that index.
            if (failing.has_induced_failure) return error.OutOfMemory;
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}

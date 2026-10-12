const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;

test "native SDK private prepareRun matches actual Source ordering ownership and failures" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try sdk.install(engine, exports);
    const constructor = try sdk.get(engine, exports, "AgentSession");
    defer engine.freeValue(constructor);
    const prototype = try sdk.get(engine, constructor, "prototype");
    defer engine.freeValue(prototype);
    // Private test binding only. Image processing, compaction, extension runner
    // and structured system-prompt/loadout rendering remain explicit inputs.
    try @import("extensions/native_sdk_session_prepare.zig").install(engine, prototype);
    try engine.registerValueModule("sdk-private-session-prepare", exports);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const original = @embedFile("extensions/fixtures/sdk-session-prepare-19cb.json");
    try sdk.put(engine, root, "prepareSource", try engine.checked(c.JS_ParseJSON(engine.context, original.ptr, original.len, "sdk-session-prepare-19cb.json")));
    const observed = engine.evalModule("import{AgentSession}from'sdk-private-session-prepare';\n" ++
        @embedFile("extensions/fixtures/sdk-session-prepare-19cb.input.txt") ++
        "\nif(sdkPrepareRows.length!==44)throw Error('Source case inventory changed');for(let index=0;index<sdkPrepareRows.length;index++)if(JSON.stringify(sdkPrepareRows[index])!==JSON.stringify(prepareSource.rows[index]))throw Error(JSON.stringify({index,actual:sdkPrepareRows[index],expected:prepareSource.rows[index]}));", "sdk-session-prepare-source.mjs") catch |err| {
        std.debug.print("Session prepareRun Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(observed);
}

test "native SDK private prepareRun retains receiver trigger queues and handler options across collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const prototype = try sdk.object(engine);
    defer engine.freeValue(prototype);
    try @import("extensions/native_sdk_session_prepare.zig").install(engine, prototype);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try sdk.put(engine, root, "preparePrototype", c.JS_DupValue(engine.context, prototype));
    const setup = try engine.eval(
        \\globalThis.prepareHeld={};(()=>{const queued={role:'custom',customType:'queued',content:[]},patch={role:'system',sections:{identity:'held'}},receiver=Object.create(preparePrototype);Object.assign(receiver,{agent:{state:{messages:[{role:'assistant'}],tools:[{name:'live'}]}},_baseSystemPromptOptions:{selectedTools:['base']},_pendingNextTurnMessages:[queued],_checkCompaction(message,continued){if(continued!==false)throw Error('continuation');return new Promise(resolve=>{prepareHeld.compact=resolve;});},_extensionRunner:{emitBeforeAgentStart(trigger,options){return new Promise(resolve=>{prepareHeld.before=()=>resolve({systemPromptOptions:{selectedTools:['base']},messages:[{customType:'handler',content:null}]});});}},_normalizePromptImages(images){return new Promise(resolve=>{prepareHeld.images=()=>resolve({images:[{type:'image',data:images[0].data,mimeType:'image/png'}],hints:['held hint']});});},_preparePromptAndToolLoadout(options){if(this!==receiver||options.selectedTools[0]!=='live'||receiver._pendingNextTurnMessages.length!==0)throw Error('lost state');return patch;}});prepareHeld.expected={queued,patch};prepareHeld.pending=preparePrototype._prepareRun.call(receiver,{messageType:'user',prompt:'held prompt',images:[{data:'held bytes'}]});})();
    , "prepare-held-setup.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(setup);
    c.JS_RunGC(engine.runtime);
    const compacted = try engine.evalModule("prepareHeld.compact();await Promise.resolve();await Promise.resolve();if(typeof prepareHeld.before!=='function')throw Error('missing handler stage');", "prepare-held-compaction.mjs");
    engine.freeValue(compacted);
    c.JS_RunGC(engine.runtime);
    const handlers = try engine.evalModule("prepareHeld.before();await Promise.resolve();await Promise.resolve();if(typeof prepareHeld.images!=='function')throw Error('missing image stage');", "prepare-held-handlers.mjs");
    engine.freeValue(handlers);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule("prepareHeld.images();const messages=await prepareHeld.pending;if(messages.length!==4||messages[0]!==prepareHeld.expected.patch||messages[2]!==prepareHeld.expected.queued||messages[1].content[0].text!=='held prompt\\n\\nheld hint'||messages[1].content[1].data!=='held bytes'||messages[3].content.length!==0)throw Error('lost preparation roots');delete globalThis.prepareHeld;", "prepare-held-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}

test "native SDK private prepareRun releases every failed native preparation allocation" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{});
            defer engine.deinit();
            const prototype = try sdk.object(engine);
            defer engine.freeValue(prototype);
            try @import("extensions/native_sdk_session_prepare.zig").install(engine, prototype);
            const root = c.JS_GetGlobalObject(engine.context);
            defer engine.freeValue(root);
            try sdk.put(engine, root, "preparePrototype", c.JS_DupValue(engine.context, prototype));
            const generation = engine.native_allocation_generation;
            const result = engine.evalModule("const receiver=Object.create(preparePrototype);Object.assign(receiver,{agent:{state:{messages:[{role:'assistant'}],tools:[{name:'live'}]}},_baseSystemPromptOptions:{selectedTools:['base']},_pendingNextTurnMessages:[{role:'custom',customType:'queued',content:[]}],_checkCompaction(){return Promise.resolve();},_extensionRunner:{emitBeforeAgentStart(){return Promise.resolve({systemPromptOptions:{selectedTools:['base']},messages:[{customType:'handler',content:null}]});}},_normalizePromptImages(){return Promise.resolve({images:[{type:'image',data:'bytes'}],hints:['hint']});},_preparePromptAndToolLoadout(){return{role:'system',sections:{identity:'patch'}};}});const messages=await preparePrototype._prepareRun.call(receiver,{messageType:'user',prompt:'prompt'});if(messages.length!==4||messages[1].content[0].text!=='prompt\\n\\nhint'||receiver._pendingNextTurnMessages.length!==0||receiver._runSystemPromptOptions.selectedTools[0]!=='live')throw Error('preparation');", "prepare-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
        }
    };
    // Record the same complete failure-index universe used by the standard
    // checker below. The extra unlimited baseline is not failure coverage.
    var measured = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try Probe.run(measured.allocator());
    try std.testing.expectEqual(measured.allocated_bytes, measured.freed_bytes);
    std.debug.print("PREPARE_RUN_ALLOCATION_UNIVERSE total={d} backing=std.testing.allocator\n", .{measured.alloc_index});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}

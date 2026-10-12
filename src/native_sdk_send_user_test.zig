const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;

test "native SDK sendUserMessage replays actual latest Source normalization and async errors" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try sdk.install(engine, exports);
    try engine.registerValueModule("sdk-send-user", exports);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const original = @embedFile("extensions/fixtures/sdk-send-user-19cb.json");
    try sdk.put(engine, root, "sendUserSource", try engine.checked(c.JS_ParseJSON(engine.context, original.ptr, original.len, "sdk-send-user-19cb.json")));
    const observed = engine.evalModule("import{AgentSession}from'sdk-send-user';\n" ++ @embedFile("extensions/fixtures/sdk-send-user-19cb.input.txt") ++
        "\nif(JSON.stringify(sdkSendUserRows)!==JSON.stringify(sendUserSource.rows))throw Error(JSON.stringify({actual:sdkSendUserRows,expected:sendUserSource.rows}));", "sdk-send-user-source.mjs") catch |err| {
        std.debug.print("sendUserMessage Source replay: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(observed);
}

test "native SDK sendUserMessage holds pending prompt receiver and image roots through collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const prototype = try sdk.object(engine);
    defer engine.freeValue(prototype);
    try @import("extensions/native_sdk_send_user.zig").install(engine, prototype);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try sdk.put(engine, root, "sendPrototype", c.JS_DupValue(engine.context, prototype));
    const setup = try engine.eval(
        \\globalThis.sendRetained={};(()=>{const image={type:'image',data:'retained'},receiver={prompt(text,options){return new Promise(resolve=>{sendRetained.finish=()=>{if(options.images[0]!==image||this!==receiver)throw Error('lost owner roots');resolve(91);};});}};sendRetained.pending=sendPrototype.sendUserMessage.call(receiver,[{type:'text',text:'held'},image]);})();
    , "send-user-retained.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(setup);
    c.JS_RunGC(engine.runtime);
    const result = try engine.evalModule("sendRetained.finish();if(await sendRetained.pending!==undefined)throw Error('return value');delete globalThis.sendRetained;", "send-user-retained-check.mjs");
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}

test "native SDK sendUserMessage native normalization and continuation release allocation failures" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{});
            defer engine.deinit();
            const prototype = try sdk.object(engine);
            defer engine.freeValue(prototype);
            try @import("extensions/native_sdk_send_user.zig").install(engine, prototype);
            const root = c.JS_GetGlobalObject(engine.context);
            defer engine.freeValue(root);
            try sdk.put(engine, root, "sendPrototype", c.JS_DupValue(engine.context, prototype));
            const generation = engine.native_allocation_generation;
            const result = engine.evalModule("const result=await sendPrototype.sendUserMessage.call({prompt(text,options){if(text!=='one\\ntwo'||options.images[0].data!=='bytes')throw Error('normalization');return Promise.resolve(17);}},[{type:'text',text:'one'},{type:'image',data:'bytes'},{type:'text',text:'two'}]);if(result!==undefined)throw Error('return');", "send-user-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}

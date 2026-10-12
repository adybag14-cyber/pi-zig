const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;

test "native SDK public message conversion matches original latest Source identities coercion and live methods" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try sdk.install(engine, exports);
    try engine.registerValueModule("sdk-message-conversion", exports);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const original = @embedFile("extensions/fixtures/sdk-message-conversion-19cb.json");
    try sdk.put(engine, root, "conversionSource", try engine.checked(c.JS_ParseJSON(engine.context, original.ptr, original.len, "sdk-message-conversion-19cb.json")));
    const result = engine.evalModule("import{convertToLlm}from'sdk-message-conversion';\n" ++
        @embedFile("extensions/fixtures/sdk-message-conversion-19cb.input.txt") ++
        "\nif(JSON.stringify(sdkMessageRows)!==JSON.stringify(conversionSource.rows))throw Error(JSON.stringify({actual:sdkMessageRows,expected:conversionSource.rows}));", "sdk-message-conversion-source.mjs") catch |err| {
        std.debug.print("SDK message conversion Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}

fn conversionAllocations(failing: *std.testing.FailingAllocator, offset: ?usize) !usize {
    const engine = try em.Engine.init(failing.allocator(), .{});
    defer engine.deinit();
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try sdk.install(engine, exports);
    try engine.registerValueModule("sdk-message-allocation", exports);
    const setup = try engine.evalModule(
        \\import{convertToLlm}from'sdk-message-allocation';globalThis.convertMessages=convertToLlm;
        \\globalThis.messageInputs=[{role:'user',content:'unchanged'},{role:'custom',content:[{type:'text',text:'custom'}],timestamp:1},{role:'bashExecution',command:'echo',output:'data',exitCode:3,truncated:true,fullOutputPath:'/owned',timestamp:2},{role:'branchSummary',summary:'branch',timestamp:3},{role:'compactionSummary',summary:'compact',timestamp:4},{role:'unknown'}];
    , "sdk-message-allocation-setup.mjs");
    engine.freeValue(setup);
    const before = failing.alloc_index;
    if (offset) |index| failing.fail_index = before + index;
    const generation = engine.native_allocation_generation;
    const result = engine.evalModule("const rows=convertMessages(messageInputs);if(rows.length!==5||rows[0]!==messageInputs[0]||rows[1].content!==messageInputs[1].content)throw Error('conversion identities');", "sdk-message-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
    return failing.alloc_index - before;
}

test "native SDK public message conversion retires every induced operation allocation" {
    var baseline = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const total = try conversionAllocations(&baseline, null);
    try std.testing.expect(total > 0);
    try std.testing.expectEqual(baseline.allocated_bytes, baseline.freed_bytes);
    for (0..total) |index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        try std.testing.expectError(error.OutOfMemory, conversionAllocations(&failing, index));
        try std.testing.expect(failing.has_induced_failure);
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    }
    std.debug.print("SDK_MESSAGE_CONVERSION_ALLOCATION_COMPLETE indices={d}\n", .{total});
}

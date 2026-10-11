const std = @import("std");
const js = @import("extensions/native_js_values.zig");
const c = js.c;
const binding = @import("extensions/native_localecompare_binding.zig");
test "Native localeCompare Coercion Source original90 noncallable primitive hooks and revoked proxies" {
    const engine = try js.Engine.init(std.testing.allocator, .{ .memory_limit = 64 * 1024 * 1024 });
    defer engine.deinit();
    // Engine.init installs native localeCompare before guest code.
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const source = @embedFile("extensions/fixtures/localecompare-node24-coercion-edge.json");
    try js.define(engine, root, "localeCompareOriginal", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "localecompare-coercion-edge-source.json")));
    const result = engine.evalModule(@embedFile("extensions/fixtures/localecompare-node24-coercion-edge.input.txt") ++
        "\nif(coercionEdgeCases.length!==90)throw Error('actual coercion edge Source count');const mismatches=[];for(let index=0;index<coercionEdgeCases.length;index++){if(JSON.stringify(coercionEdgeCases[index])!==JSON.stringify(localeCompareOriginal.cases[index]))mismatches.push({index,actual:coercionEdgeCases[index],expected:localeCompareOriginal.cases[index]});}if(mismatches.length)throw Error(JSON.stringify({mismatchCount:mismatches.length,mismatches}));", "native-localecompare-coercion-edge-source.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native localeCompare coercion edge Source failure: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}

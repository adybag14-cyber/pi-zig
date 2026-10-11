const std = @import("std");
const js = @import("extensions/native_js_values.zig");
const c = js.c;
const binding = @import("extensions/native_localecompare_binding.zig");
test "Native localeCompare Source original69 API coercion getter chronology exceptions and genuine metadata" {
    const engine = try js.Engine.init(std.testing.allocator, .{ .memory_limit = 64 * 1024 * 1024 });
    defer engine.deinit();
    // Engine.init installs native localeCompare before guest code.
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const source = @embedFile("extensions/fixtures/localecompare-node24-api.json");
    try js.define(engine, root, "localeCompareOriginal", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "localecompare-original-api.json")));
    const result = engine.evalModule(@embedFile("extensions/fixtures/localecompare-node24-api.input.txt") ++
        "\nif(cases.length!==69)throw Error('actual localeCompare API Source count');for(let index=0;index<cases.length;index++){if(JSON.stringify(cases[index])!==JSON.stringify(localeCompareOriginal.cases[index]))throw Error(JSON.stringify({index,actual:cases[index],expected:localeCompareOriginal.cases[index]}));}if(JSON.stringify(metadata)!==JSON.stringify(localeCompareOriginal.metadata))throw Error(JSON.stringify({actual:metadata,expected:localeCompareOriginal.metadata}));", "native-localecompare-original-api.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native actual localeCompare API Source failure: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "Native localeCompare Source original2100 full JS locale option and lossless UTF16 comparisons" {
    const engine = try js.Engine.init(std.testing.allocator, .{ .memory_limit = 64 * 1024 * 1024 });
    defer engine.deinit();
    // Engine.init installs native localeCompare before guest code.
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const source = @embedFile("extensions/fixtures/localecompare-node24-typed.json");
    try js.define(engine, root, "localeCompareOriginal", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "localecompare-original-typed.json")));
    const result = engine.evalModule(
        \\if(localeCompareOriginal.cases.length!==2100)throw Error('actual localeCompare typed Source count');
        \\for(let index=0;index<localeCompareOriginal.cases.length;index++){
        \\ const expected=localeCompareOriginal.cases[index],wire=expected.options,options={sensitivity:wire.sensitivity};
        \\ if(wire.numeric!==null)options.numeric=wire.numeric;
        \\ if(wire.case_first!==null)options.caseFirst=wire.case_first;
        \\ if(wire.ignore_punctuation!==null)options.ignorePunctuation=wire.ignore_punctuation;
        \\ const left=String.fromCharCode(...expected.left),right=String.fromCharCode(...expected.right);
        \\ const actual=Math.sign(left.localeCompare(right,expected.locale,options));
        \\ if(actual!==expected.result)throw Error(JSON.stringify({index,actual,expected}));
        \\}
    , "native-localecompare-original-typed.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native actual localeCompare typed JS Source failure: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}

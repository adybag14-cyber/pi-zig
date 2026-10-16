//! Requires original expected evidence; never creates expected values.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;

test "minimatch AST depth adoption flattening and negative tails match original controls" {
    const expected = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "src/extensions/fixtures/minimatch-10.2.6.ast.expected.json", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(expected);
    const receipt = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "verification/minimatch-10.2.6-ast-source-only-20261016.json", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(receipt);
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "minimatchAPI", try @import("extensions/native_minimatch_namespace.zig").create(engine));
    const cases = @embedFile("extensions/fixtures/minimatch-10.2.6.ast.cases.json");
    try sdk.put(engine, global, "minimatchCases", try engine.checked(c.JS_ParseJSON(engine.context, cases.ptr, cases.len, "minimatch.ast.cases.json")));
    try sdk.put(engine, global, "minimatchExpected", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "minimatch.ast.expected.json")));
    try sdk.put(engine, global, "minimatchReceipt", try engine.checked(c.JS_ParseJSON(engine.context, receipt.ptr, receipt.len, "minimatch.ast.receipt.json")));
    try sdk.put(engine, global, "nativePlatform", try sdk.text(engine, if (@import("builtin").os.tag == .windows) "win32" else "posix"));
    const result = engine.evalModule(
        \\const want=minimatchExpected;if(want.kind!=='original-minimatch-ast-control'||want.baseCommit!=='7af3116b051bf6f087e4c5a40ed35bbdb6ca4af9'||want.sourceHead!=='4dd2b149d155d7369de16ea4dc77c84e9f5ffb24'||want.minimatchVersion!=='10.2.6')throw Error('wrong original AST authority');
        \\if((want.platform==='win32')!==(nativePlatform==='win32'))throw Error('oracle/native platform mismatch');
        \\if(want.casesSha256!==minimatchReceipt.casesSha256||minimatchCases.length!==want.rows.length)throw Error('AST input identity drift');
        \\for(let i=0;i<minimatchCases.length;i++){const row=minimatchCases[i],expected=want.rows[i];let got;try{got={id:row.id,result:minimatchAPI.minimatch(row.path,row.pattern,row.options)}}catch(error){got={id:row.id,errorName:error.name}}if(JSON.stringify(got)!==JSON.stringify(expected))throw Error(JSON.stringify({id:row.id,got,expected}));}
        \\export const complete=true;
    , "native-minimatch-original-ast.mjs") catch |err| {
        std.debug.print("Minimatch AST differential: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}

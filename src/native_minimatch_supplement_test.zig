//! Original-only expected evidence remains mandatory and absent until leased.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;

fn verify(comptime suite: []const u8, cases: []const u8) !void {
    const expected = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "src/extensions/fixtures/minimatch-10.2.6." ++ suite ++ ".expected.json", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(expected);
    const receipt = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "verification/minimatch-10.2.6-supplement-source-only-20261016.json", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(receipt);
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "minimatchAPI", try @import("extensions/native_minimatch_namespace.zig").create(engine));
    try sdk.put(engine, global, "minimatchCases", try engine.checked(c.JS_ParseJSON(engine.context, cases.ptr, cases.len, "minimatch.supplement.cases.json")));
    try sdk.put(engine, global, "minimatchExpected", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "minimatch.supplement.expected.json")));
    try sdk.put(engine, global, "minimatchReceipt", try engine.checked(c.JS_ParseJSON(engine.context, receipt.ptr, receipt.len, "minimatch.supplement.receipt.json")));
    try sdk.put(engine, global, "nativePlatform", try sdk.text(engine, if (@import("builtin").os.tag == .windows) "win32" else "posix"));
    try sdk.put(engine, global, "minimatchSuite", try sdk.text(engine, suite));
    const result = engine.evalModule(
        \\const want=minimatchExpected;if(want.kind!=='original-dependency-control-supplement'||want.baseCommit!=='d849736a0c7d2d73bf63711b6f99a6bd76469b06'||want.sourceHead!=='4dd2b149d155d7369de16ea4dc77c84e9f5ffb24'||want.minimatchVersion!=='10.2.6'||want.suite!==minimatchSuite)throw Error('wrong original supplement authority');
        \\if((want.platform==='win32')!==(nativePlatform==='win32'))throw Error('oracle/native platform mismatch');
        \\if(want.casesSha256!==minimatchReceipt.suites[minimatchSuite].sha256||minimatchCases.length!==want.rows.length)throw Error('supplement identity drift');
        \\for(let i=0;i<minimatchCases.length;i++){const row=minimatchCases[i],expected=want.rows[i];let got;try{got={id:row.id,result:minimatchAPI.minimatch(row.path,row.pattern,row.options)}}catch(error){got={id:row.id,errorName:error.name}}if(JSON.stringify(got)!==JSON.stringify(expected))throw Error(JSON.stringify({id:row.id,got,expected}));}
        \\export const complete=true;
    , "native-minimatch-original-supplement.mjs") catch |err| {
        std.debug.print("Minimatch supplement differential: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}

test "minimatch valid line breaks and terminal globstars match original controls" {
    try verify("linebreak-globstar", @embedFile("extensions/fixtures/minimatch-10.2.6.linebreak-globstar.cases.json"));
}
test "minimatch astral classes retain original UTF16 unit semantics" {
    try verify("astral-classes", @embedFile("extensions/fixtures/minimatch-10.2.6.astral-classes.cases.json"));
}

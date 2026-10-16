//! Differential gate intentionally requires an original-dependency result file.
//! No native implementation path creates or replaces that expected evidence.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;

test "minimatch named component matches original 10.2.6 controls" {
    const expected = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "src/extensions/fixtures/minimatch-10.2.6.expected.json", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(expected);
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "minimatchAPI", try @import("extensions/native_minimatch_namespace.zig").create(engine));
    const cases = @embedFile("extensions/fixtures/minimatch-10.2.6.cases.json");
    try sdk.put(engine, global, "minimatchCases", try engine.checked(c.JS_ParseJSON(engine.context, cases.ptr, cases.len, "minimatch.cases.json")));
    try sdk.put(engine, global, "minimatchExpected", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "minimatch.expected.json")));
    const provenance = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "verification/minimatch-10.2.6-source-only-20261016.json", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(provenance);
    try sdk.put(engine, global, "minimatchProvenance", try engine.checked(c.JS_ParseJSON(engine.context, provenance.ptr, provenance.len, "minimatch.provenance.json")));
    try sdk.put(engine, global, "nativePlatform", try sdk.text(engine, if (@import("builtin").os.tag == .windows) "win32" else "posix"));
    const result = engine.evalModule(
        \\if(minimatchExpected.kind!=='original-dependency-control'||minimatchExpected.minimatchVersion!=='10.2.6'||minimatchExpected.sourceHead!=='4dd2b149d155d7369de16ea4dc77c84e9f5ffb24')throw Error('wrong original authority');
        \\if((minimatchExpected.platform==='win32')!==(nativePlatform==='win32'))throw Error('oracle/native platform mismatch');
        \\for(const item of minimatchProvenance.sourceFiles){const key=item.name==='packageManager'?'caller':item.name;if(minimatchExpected.hashes[key]!==item.sha256)throw Error('original source identity drift: '+key);}
        \\if(minimatchCases.length!==minimatchExpected.rows.length)throw Error('missing original rows');
        \\for(let i=0;i<minimatchCases.length;i++){const row=minimatchCases[i],want=minimatchExpected.rows[i];if(row.id!==want.id)throw Error('case identity drift');const got=minimatchAPI.minimatch(row.path,row.pattern,row.options);if(got!==want.result)throw Error(JSON.stringify({id:row.id,got,want:want.result}));}
        \\export const complete=true;
    , "native-minimatch-original-controls.mjs") catch |err| {
        std.debug.print("Minimatch differential: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}

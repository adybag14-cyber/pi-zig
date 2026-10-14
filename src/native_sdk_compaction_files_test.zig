const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;
fn install(engine: *em.Engine) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "compactionFilesAPI", try @import("extensions/native_sdk_compaction_files.zig").exports(engine));
}
test "native SDK compaction files matches24 original tracking ordering coercion and function observations" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("extensions/fixtures/sdk-compaction-files-1692.json");
    try sdk.put(engine, global, "compactionFilesSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "sdk-compaction-files-1692.json")));
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-compaction-files-1692.input.txt") ++
        "\nif(compactionFilesSource.sourceHead!=='1692bba6347a287ab0f3cb554a4430fafffc474b'||compactionFilesRows.length!==24||compactionFilesSource.rows.length!==24)throw Error('24 original observations required');for(let i=0;i<24;i++)if(JSON.stringify(compactionFilesRows[i])!==JSON.stringify(compactionFilesSource.rows[i]))throw Error(JSON.stringify({case:i,actual:compactionFilesRows[i],expected:compactionFilesSource.rows[i]}));", "native-sdk-compaction-files-source.mjs") catch |err| {
        std.debug.print("Compaction files Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native SDK compaction files retained functions and constructors survive collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const prepared = try engine.evalModule(
        \\globalThis.retainedFiles=compactionFilesAPI;delete globalThis.compactionFilesAPI;export const prepared=true;
    , "native-sdk-compaction-files-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\const ops=new retainedFiles.createFileOps();retainedFiles.extractFileOpsFromMessage({role:'assistant',content:[{type:'toolCall',name:'read',arguments:{path:'a'}}]},ops);const lists=new retainedFiles.computeFileLists(ops);if(lists.readFiles.join(',')!=='a'||retainedFiles.formatFileOperations(lists.readFiles,lists.modifiedFiles)!=='\n\n<read-files>\na\n</read-files>')throw Error('retained files export');delete globalThis.retainedFiles;export const completed=true;
    , "native-sdk-compaction-files-gc-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK compaction files every native allocation releases constructors iterators sets and formatting roots" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            install(engine) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule(
                \\const f=compactionFilesAPI,ops=f.createFileOps();f.extractFileOpsFromMessage({role:'assistant',content:[{type:'toolCall',name:'read',arguments:{path:'a'}},{type:'toolCall',name:'write',arguments:{path:'b'}}]},ops);f.extractFileOpsFromMessage({role:'toolResult',nestedCalls:{calls:[{name:'edit',arguments:{path:'c'}}]}},ops);const lists=f.computeFileLists(ops);if(lists.readFiles.join(',')!=='a'||lists.modifiedFiles.join(',')!=='b,c'||!f.formatFileOperations(lists.readFiles,lists.modifiedFiles).includes('<modified-files>'))throw Error('file tracking');const marker={},calls={*[Symbol.iterator](){try{yield{get name(){throw marker;}};}finally{}}};try{f.extractFileOpsFromMessage({role:'toolResult',nestedCalls:{calls}},ops);throw Error('expected getter failure');}catch(error){if(error!==marker)throw error;}export const proof=true;
            , "native-sdk-compaction-files-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}

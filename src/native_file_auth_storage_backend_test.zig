//! Actual ordinary-class Source32 replay using real owned temporary files.
const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const c = em.c;
fn install(engine: *em.Engine, root: []const u8) !void {
    var environment = try std.testing.environ.createMap(engine.gpa);
    defer environment.deinit();
    try environment.put("PI_CODING_AGENT_DIR", root);
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{});
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/abort_signal.zig").install(engine);
    try @import("extensions/native_url.zig").install(engine);
    try @import("extensions/node_fs.zig").install(engine, std.testing.io);
    try @import("extensions/node_path.zig").install(engine, std.testing.io);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "FileAuthStorageBackend", try scope.own(try @import("extensions/native_auth_file_storage_backend.zig").createDefault(engine)));
    try scope.put(global, "fileAuthFs", engine.native_module_values.get("node:fs").?);
    try scope.put(global, "fileAuthLockfile", try scope.own(try @import("extensions/native_auth_directory_lock.zig").create(engine)));
    try scope.put(global, "fileAuthJoin", try scope.get(engine.native_module_values.get("node:path").?, "join"));
    try scope.put(global, "fileAuthSleep", try scope.get(engine.native_module_values.get("timers/promises").?, "setTimeout"));
    try scope.put(global, "fileAuthRoot", try scope.text(root));
}
test "native FileAuthStorageBackend actual Source32 ordinary class filesystem leases callbacks abort and retries" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const size = try temporary.dir.realPath(std.testing.io, &buffer);
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10_000 });
    defer engine.deinit();
    try install(engine, buffer[0..size]);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const expected = @embedFile("extensions/fixtures/sdk-file-auth-storage-4954.json");
    try scope.put(try scope.own(c.JS_GetGlobalObject(engine.context)), "fileAuthSource", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "actual-4954-FileAuth32.json"))));
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-file-auth-storage-4954.input.txt") ++
        \\if(fileAuthSource.sourceHead!=='4954d760504c11df9b2cbdc040346107b6a8153d'||fileAuthSource.count!==32||fileAuthObservedRows.length!==32)throw Error('genuine FileAuth32 inventory required');
        \\for(let index=0;index<32;index++)if(JSON.stringify(fileAuthObservedRows[index])!==JSON.stringify(fileAuthSource.rows[index]))throw Error(JSON.stringify({index,actual:fileAuthObservedRows[index],expected:fileAuthSource.rows[index]}));
    , "native-file-auth-Source4954-32.mjs") catch |err| {
        std.debug.print("FileAuth Source32: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native FileAuthStorageBackend ordinary subclass and pending callback lease survive GC" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const size = try temporary.dir.realPath(std.testing.io, &buffer);
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10_000 });
    defer engine.deinit();
    try install(engine, buffer[0..size]);
    const prepared = try engine.evalModule(
        \\class Derived extends FileAuthStorageBackend{}const backend=new Derived(fileAuthJoin(fileAuthRoot,'retained','auth.json'));if(!(backend instanceof Derived)||!(backend instanceof FileAuthStorageBackend))throw Error('ordinary subclass');let finish,started;const start=new Promise(resolve=>started=resolve),blocked=new Promise(resolve=>finish=resolve);globalThis.retainedFileAuth={backend,finish:()=>finish(),work:backend.withLockAsync(async()=>{started();await blocked;return {result:'retained',next:'after-gc'};})};await start;delete globalThis.FileAuthStorageBackend;export const ready=true;
    , "native-file-auth-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\if(!fileAuthFs.existsSync(retainedFileAuth.backend.authPath+'.lock'))throw Error('pending lease released');retainedFileAuth.finish();if(await retainedFileAuth.work!=='retained'||fileAuthFs.readFileSync(retainedFileAuth.backend.authPath,'utf-8')!=='after-gc'||fileAuthFs.existsSync(retainedFileAuth.backend.authPath+'.lock'))throw Error('retained callback commit/release');delete globalThis.retainedFileAuth;export const done=true;
    , "native-file-auth-gc-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}

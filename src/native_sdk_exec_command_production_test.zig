const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const exec = @import("extensions/native_sdk_exec_command_production.zig");
const c = em.c;
fn install(engine: *em.Engine, root: []const u8, child: []const u8) !void {
    var env: std.process.Environ.Map = .init(std.testing.allocator);
    defer env.deinit();
    try env.put("SystemRoot", "C:\\Windows");
    try env.put("HOME", root);
    try env.put("USERPROFILE", root);
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &env, &.{});
    try @import("extensions/node_buffer.zig").install(engine);
    try @import("extensions/abort_signal.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const global = try s.own(c.JS_GetGlobalObject(engine.context));
    try sdk.put(engine, global, "execCommand", try exec.create(engine));
    try s.put(global, "fixtureRoot", try s.text(root));
    try s.put(global, "fixtureChild", try s.text(child));
    try s.put(global, "fixtureNode", try s.text("C:/Program Files/nodejs/node.exe"));
}
test "native SDK execCommand actual real-child argv channels bytes no maxBuffer and callable shape" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    const a = std.testing.allocator;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDir(std.testing.io, "sdk-exec-owned-native-basic", .default_dir);
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, "sdk-exec-owned-native-basic", a);
    defer a.free(root);
    const child = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, "verification/native-sdk-exec-command-20261015/owned-child.mjs", a);
    defer a.free(child);
    const engine = try em.Engine.init(a, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine, root, child);
    const result = try engine.evalModule(
        \\if(execCommand.name!=='execCommand'||execCommand.length!==4||Object.prototype.toString.call(execCommand)!=='[object AsyncFunction]'||Object.hasOwn(execCommand,'prototype'))throw Error('callable shape');let construction=false;try{new execCommand()}catch(error){construction=error instanceof TypeError}if(!construction)throw Error('constructible');
        \\const call=(id,mode,extra=[],options)=>execCommand(fixtureNode,[fixtureChild,mode,fixtureRoot,id,'native-basic',...extra],fixtureRoot,options);const argv=await call('argv','argv',['a b','&|><','€','']);if(argv.stdout!==JSON.stringify(['a b','&|><','€',''])||argv.stderr!==''||argv.code!==0||argv.killed)throw Error('argv expanded');
        \\const channels=await call('channels','channels');if(channels.stdout!=='out\0\x1b[31m\n'||channels.stderr!=='err\n')throw Error('channels merged or sanitized');const failed=await call('nonzero','nonzero');if(failed.code!==17||failed.killed||failed.stdout!=='before-exit'||failed.stderr!=='diagnostic')throw Error('exit or captured channels');
        \\const invalid=await call('invalid','bytes');if(invalid.stdout!=='�(�\0\x1b')throw Error('UTF8 replacement');const split=await call('split','split');if(split.stdout!=='���')throw Error('chunk decoding carried UTF8 bytes across data callbacks');
        \\const large=await call('large','large');if(large.stdout.length!==1048593||large.stderr!=='tail'||large.code!==0)throw Error('invented maxBuffer');const options={};for(const key of ['cwd','env','shell','maxBuffer','onData'])Object.defineProperty(options,key,{get(){throw Error('ignored option '+key)}});const ignored=await call('ignored','channels',[],options);if(ignored.code!==0)throw Error('ignored option');globalThis.gcResult=large.stdout.length;export const done=true;
    , "native-sdk-exec-real-children.mjs");
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native SDK execCommand actual timeout abort and descendant stdio idle rearm" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    const a = std.testing.allocator;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDir(std.testing.io, "sdk-exec-owned-native-lifecycle", .default_dir);
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, "sdk-exec-owned-native-lifecycle", a);
    defer a.free(root);
    const child = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, "verification/native-sdk-exec-command-20261015/owned-child.mjs", a);
    defer a.free(child);
    const engine = try em.Engine.init(a, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine, root, child);
    const result = try engine.evalModule(
        \\const call=(id,mode,options)=>execCommand(fixtureNode,[fixtureChild,mode,fixtureRoot,id,'native-lifecycle'],fixtureRoot,options);const expired=await call('timeout','sleep',{timeout:60});if(!expired.killed||expired.code!==1)throw Error('timeout must kill direct Windows child');const disabled=await call('disabled','sleep',{timeout:0});if(disabled.killed||disabled.code!==0||disabled.stdout!=='natural-end')throw Error('zero timeout');
        \\const controller=new AbortController();controller.abort('caller reason');const aborted=await call('preaborted','sleep',{signal:controller.signal});if(!aborted.killed||aborted.code!==1)throw Error('preabort result');const active=new AbortController();setTimeout(()=>active.abort(),80);const canceled=await call('active','sleep',{signal:active.signal});if(!canceled.killed||canceled.code!==1)throw Error('active abort');
        \\const quietStarted=performance.now();const quiet=await call('quiet','descendant-quiet');if(quiet.code!==0||performance.now()-quietStarted>1500)throw Error('quiet inherited pipe hung');const activeTail=await call('tail','descendant-active');if(activeTail.stdout!=='abcd'||activeTail.stderr!=='end')throw Error('post-exit active tail truncated');await new Promise(resolve=>setTimeout(resolve,750));export const done=true;
    , "native-sdk-exec-owned-lifecycle.mjs");
    engine.freeValue(result);
}

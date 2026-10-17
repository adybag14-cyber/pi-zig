//! Additive prepared controls; frozen313+6 originals and nine native entries
//! remain byte-exact. No authored expected JSON or execution evidence.
const std=@import("std");
const em=@import("extensions/engine.zig");
const js=@import("extensions/native_js_values.zig");
const c=em.c;
fn install(engine:*em.Engine)!void{
    const bindings=try @import("extensions/native_pathe.zig").create(engine);defer engine.freeValue(bindings);
    const subject=try js.object(engine);defer engine.freeValue(subject);try js.define(engine,subject,"path",c.JS_DupValue(engine.context,bindings));try js.define(engine,subject,"utils",c.JS_DupValue(engine.context,bindings));
    const global=c.JS_GetGlobalObject(engine.context);defer engine.freeValue(global);try js.define(engine,global,"nativePatheSubject",c.JS_DupValue(engine.context,subject));
}
test "native jiti pathe compares40 additional original resolve and filename observations"{
    const expected=try std.Io.Dir.cwd().readFileAlloc(std.testing.io,"src/extensions/fixtures/jiti-pathe-cache-2.0.3.json",std.testing.allocator,.limited(1024*1024));defer std.testing.allocator.free(expected);
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();try install(engine);
    const terminated=try engine.gpa.dupeZ(u8,expected);defer engine.gpa.free(terminated);const original=try engine.checked(c.JS_ParseJSON(engine.context,terminated.ptr,expected.len,"original-pathe-cache.json"));defer engine.freeValue(original);
    const global=c.JS_GetGlobalObject(engine.context);defer engine.freeValue(global);try js.define(engine,global,"originalPatheCache",c.JS_DupValue(engine.context,original));
    const value=try engine.evalModule(@embedFile("extensions/fixtures/jiti-pathe-cache-2.0.3.input.mjs") ++
        \\if(nativePatheCacheObservation.count!==40||originalPatheCache.count!==40)throw Error('Complete40 original observations required');for(let i=0;i<40;i++)if(JSON.stringify(nativePatheCacheObservation.rows[i])!==JSON.stringify(originalPatheCache.rows[i]))throw Error(JSON.stringify({index:i,actual:nativePatheCacheObservation.rows[i],original:originalPatheCache.rows[i]}));
    ,"native-jiti-pathe-cache-original.mjs");engine.freeValue(value);
}
test "native jiti pathe cache functions and slash constant retain roots through GC"{
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();try install(engine);
    const before=try engine.evalModule(
        \\globalThis.retainedPatheFilename=nativePatheSubject.utils.filename;globalThis.retainedPatheResolve=nativePatheSubject.path.resolve;
    ,"native-pathe-cache-before-gc.mjs");engine.freeValue(before);c.JS_RunGC(engine.runtime);
    const after=try engine.evalModule(
        \\if(retainedPatheFilename!==nativePatheSubject.utils.filename||retainedPatheResolve!==nativePatheSubject.path.resolve)throw Error('function identity');if(retainedPatheFilename('c:\\folder\\file.ts')!=='file'||retainedPatheResolve('c:\\a','b')!=='C:/a/b')throw Error('retained native roots');
    ,"native-pathe-cache-after-gc.mjs");engine.freeValue(after);
}
fn allocationCase(gpa:std.mem.Allocator)!void{
    const engine=try em.Engine.init(gpa,.{});defer engine.deinit();const generation=engine.native_allocation_generation;
    install(engine) catch |err| return engine.nativeAllocationError(err,generation);
    const value=engine.evalModule(
        \\nativePatheSubject.path.resolve('c:\\a','..','é🌍');nativePatheSubject.utils.filename('a/é🌍.ts');
    ,"native-pathe-cache-gpa.mjs") catch |err| return engine.nativeAllocationError(err,generation);engine.freeValue(value);
}
test "native jiti pathe resolve and filename complete allocation cleanup"{try std.testing.checkAllAllocationFailures(std.testing.allocator,allocationCase,.{});}

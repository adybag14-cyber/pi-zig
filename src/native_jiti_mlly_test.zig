//! Prepared genuine-original replay + native ownership controls. These tests
//! require the actual node:module builtinModules seam; no local substitute.
const std=@import("std");
const em=@import("extensions/engine.zig");
const m=@import("extensions/native_mlly_values.zig");
const mlly=@import("extensions/native_mlly_resolve.zig");
const js=m.v.js;
const c=m.c;
fn setup(engine:*em.Engine) !void {
    var s:m.Scope=.{.engine=engine};defer s.deinit();
    const imports=try s.own(try engine.evalModule(
        \\import fs from 'node:fs';import path from 'node:path';import process from 'node:process';import {builtinModules} from 'node:module';import * as nodeURL from 'node:url';
        \\export {fs,path,process,builtinModules,nodeURL};export const fixtureRootURL=nodeURL.pathToFileURL(path.resolve('src/extensions/fixtures/jiti-mlly-tree')+path.sep);
    ,"native-mlly-actual-imports.mjs"));
    const pathe=try s.own(try @import("extensions/native_pathe.zig").create(engine));
    const node_url=try s.get(imports,"nodeURL"); const fs=try s.get(imports,"fs");
    const bindings=try s.own(try mlly.create(engine,.{
        .fs=fs,.path=try s.get(imports,"path"),.process=try s.get(imports,"process"),.builtin_modules=try s.get(imports,"builtinModules"),
        .file_url_to_path=try s.get(node_url,"fileURLToPath"),.path_to_file_url=try s.get(node_url,"pathToFileURL"),
        .stat_sync=try s.get(fs,"statSync"),.realpath_sync=try s.get(fs,"realpathSync"),
        .pathe_is_absolute=try s.get(pathe,"isAbsolute"),.pathe_normalize=try s.get(pathe,"normalize"),
    }));
    const subject=try s.object();try m.define(&s,subject,"mlly",bindings);try m.define(&s,subject,"nodeURL",node_url);try m.define(&s,subject,"fs",fs);try m.define(&s,subject,"process",try s.get(imports,"process"));try m.define(&s,subject,"fixtureRootURL",try s.get(imports,"fixtureRootURL"));
    const global=try s.own(c.JS_GetGlobalObject(engine.context));try m.define(&s,global,"nativeMllySubject",subject);
}
test "native jiti mlly compares all51 original path exports conditions cache and physical observations" {
    const expected=try std.Io.Dir.cwd().readFileAlloc(std.testing.io,"src/extensions/fixtures/jiti-mlly-1.8.2.json",std.testing.allocator,.limited(4*1024*1024));defer std.testing.allocator.free(expected);
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();try setup(engine);
    const terminated=try engine.gpa.dupeZ(u8,expected);defer engine.gpa.free(terminated);
    const parsed=try engine.checked(c.JS_ParseJSON(engine.context,terminated.ptr,expected.len,"actual-mlly-original.json"));defer engine.freeValue(parsed);
    const global=c.JS_GetGlobalObject(engine.context);defer engine.freeValue(global);try js.define(engine,global,"originalMllyObservation",c.JS_DupValue(engine.context,parsed));
    const value=try engine.evalModule(@embedFile("extensions/fixtures/jiti-mlly-1.8.2.input.mjs") ++
        \\if(nativeMllyObservation.count!==51||originalMllyObservation.count!==51)throw Error('Complete original51 required');for(let i=0;i<51;i++)if(JSON.stringify(nativeMllyObservation.rows[i])!==JSON.stringify(originalMllyObservation.rows[i]))throw Error(JSON.stringify({index:i,actual:nativeMllyObservation.rows[i],original:originalMllyObservation.rows[i]}));
    ,"native-jiti-mlly-original.mjs");engine.freeValue(value);
}
test "native jiti mlly module roots retain actual functions caches and URL bindings through GC" {
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();try setup(engine);
    const before=try engine.evalModule(
        \\const {mlly,fixtureRootURL}=nativeMllySubject;globalThis.retainedResolve=mlly.resolvePathSync;globalThis.beforeMllyPath=retainedResolve('conditional',{url:new URL('entry.mjs',fixtureRootURL)});
    ,"native-jiti-mlly-before-gc.mjs");engine.freeValue(before);c.JS_RunGC(engine.runtime);
    const after=try engine.evalModule(
        \\if(nativeMllySubject.mlly.resolvePathSync!==retainedResolve)throw Error('function identity');const result=retainedResolve('conditional',{url:new URL('entry.mjs',nativeMllySubject.fixtureRootURL)});if(result!==beforeMllyPath)throw Error('cache/URL roots lost');
    ,"native-jiti-mlly-after-gc.mjs");engine.freeValue(after);
}
fn allocationCase(gpa:std.mem.Allocator) !void {
    const engine=try em.Engine.init(gpa,.{});defer engine.deinit();const generation=engine.native_allocation_generation;
    setup(engine) catch |err| return engine.nativeAllocationError(err,generation);
    const value=engine.evalModule(
        \\const {mlly,fixtureRootURL}=nativeMllySubject;const base=new URL('entry.mjs',fixtureRootURL);for(const name of ['conditional','conditional/feature/a','#local','legacy']){const value=mlly.resolvePathSync(name,{url:base});if(typeof value!=='string')throw Error('physical resolution required')}
    ,"native-jiti-mlly-allocation.mjs") catch |err| return engine.nativeAllocationError(err,generation);engine.freeValue(value);
}
test "native jiti mlly complete GPA allocation cleanup through physical package traversal" {try std.testing.checkAllAllocationFailures(std.testing.allocator,allocationCase,.{});}

fn raiseAllocation(context:?*c.JSContext,_:c.JSValue,_:c_int,_:[*c]c.JSValue) callconv(.c)c.JSValue {
    const engine=em.Engine.fromContext(context.?);_=engine.throwNativeOutOfMemory();const reason=c.JS_GetException(context);
    const global=c.JS_GetGlobalObject(context);defer engine.freeValue(global);
    if(c.JS_DefinePropertyValueStr(context,global,"ownedMllyFatalReason",c.JS_DupValue(context,reason),c.JS_PROP_C_W_E)<0){engine.freeValue(reason);return c.JS_Throw(context,c.JS_GetException(context));}
    return c.JS_Throw(context,reason);
}
fn installFailure(engine:*em.Engine) !c.JSValue {
    const global=c.JS_GetGlobalObject(engine.context);errdefer engine.freeValue(global);
    try js.define(engine,global,"raiseOwnedMllyAllocation",try engine.checked(c.JS_NewCFunction(engine.context,raiseAllocation,"raiseOwnedMllyAllocation",0)));return global;
}
fn exactFatal(engine:*em.Engine,global:c.JSValue) !void {
    const original=try js.get(engine,global,"ownedMllyFatalReason");defer engine.freeValue(original);
    const reason=engine.captured_exception orelse return error.MissingMllyFatalReason;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context,original,reason));try std.testing.expect(c.JS_IsUncatchableError(reason));
    const caught=try js.get(engine,global,"mllyGuestCaught");defer engine.freeValue(caught);try std.testing.expectEqual(@as(c_int,0),c.JS_ToBool(engine.context,caught));
}
test "native jiti mlly package read catch code getter preserves fresh fatal identity" {
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();try setup(engine);
    const global=try installFailure(engine);defer engine.freeValue(global);
    try std.testing.expectError(error.JavaScriptException,engine.evalModule(
        \\globalThis.mllyGuestCaught=false;const fs=nativeMllySubject.fs,original=fs.readFileSync;fs.readFileSync=function(){throw{get code(){raiseOwnedMllyAllocation()}}};try{nativeMllySubject.mlly.resolveSync('conditional',{url:new URL('entry.mjs',nativeMllySubject.fixtureRootURL)})}catch{globalThis.mllyGuestCaught=true}finally{fs.readFileSync=original}
    ,"native-jiti-mlly-catch-fatal.mjs"));try exactFatal(engine,global);
}
test "native jiti mlly JSON parse source catch message getter preserves fresh fatal identity" {
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();try setup(engine);
    const global=try installFailure(engine);defer engine.freeValue(global);
    try std.testing.expectError(error.JavaScriptException,engine.evalModule(
        \\globalThis.mllyGuestCaught=false;const original=JSON.parse;JSON.parse=function(){throw{get message(){raiseOwnedMllyAllocation()}}};try{nativeMllySubject.mlly.resolveSync('conditional',{url:new URL('entry.mjs',nativeMllySubject.fixtureRootURL)})}catch{globalThis.mllyGuestCaught=true}finally{JSON.parse=original}
    ,"native-jiti-mlly-parse-catch-fatal.mjs"));try exactFatal(engine,global);
}

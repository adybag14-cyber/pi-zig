//! Prepared actual primitive, physical-input and original-comparison controls.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const crypto = @import("extensions/native_jiti_crypto.zig");
const utils = @import("extensions/native_jiti_utils.zig");
const budget = @import("extensions/native_jiti_budget.zig");
fn install(engine: *v.em.Engine, name: [*:0]const u8, value: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try v.js.define(engine, global, name, c.JS_DupValue(engine.context, value));
}
test "jiti MD5 actual incremental primitives retain private state and standard vectors" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const namespace = try crypto.create(engine); defer engine.freeValue(namespace);
    try install(engine, "ActualJitiCrypto", namespace);
    const setup = try engine.evalModule(
        \\if(ActualJitiCrypto.getFips()!==0)throw Error('actual Zig backend unexpectedly claims FIPS');
        \\if(ActualJitiCrypto.createHash('md5').update('').digest('hex')!=='d41d8cd98f00b204e9800998ecf8427e')throw Error('MD5 empty vector');
        \\globalThis.heldJitiMD5=ActualJitiCrypto.createHash('md5');if(heldJitiMD5.update('a')!==heldJitiMD5)throw Error('MD5 update identity');globalThis.heldJitiUpdate=heldJitiMD5.update;
    , "jiti-md5-state-before-gc.mjs"); engine.freeValue(setup);
    c.JS_RunGC(engine.runtime);
    const checked = try engine.evalModule(
        \\heldJitiUpdate.call(heldJitiMD5,'bc');if(heldJitiMD5.digest('hex')!=='900150983cd24fb0d6963f7d28e17f72')throw Error('MD5 abc vector/opaque ownership');let rejected=false;try{heldJitiMD5.update('late')}catch{rejected=true}if(!rejected)throw Error('MD5 finalized state');
        \\if(ActualJitiCrypto.createHash('sha256').update('abc').digest('hex')!=='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')throw Error('real qualified SHA256 delegate');delete globalThis.heldJitiMD5;delete globalThis.heldJitiUpdate;
    , "jiti-md5-state-after-gc.mjs"); engine.freeValue(checked);
    c.JS_RunGC(engine.runtime);
}
test "jiti MD5 every Zig allocation releases partial callable and hash reservations" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try v.em.Engine.init(gpa, .{}); defer engine.deinit();
            const generation = engine.native_allocation_generation;
            const namespace = crypto.create(engine) catch |err| return engine.nativeAllocationError(err, generation);
            defer engine.freeValue(namespace);
            install(engine, "ActualJitiCrypto", namespace) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule("ActualJitiCrypto.createHash('md5').update('é🌍').digest('hex');", "jiti-md5-gpa.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result); c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
test "jiti local cancellation guard marks its actual error and does not classify guest lookalikes" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    _ = c.JS_ThrowInternalError(engine.context, "interrupted");
    const lookalike = c.JS_GetException(engine.context); defer engine.freeValue(lookalike);
    try std.testing.expect(!c.JS_IsUncatchableError(lookalike));
    try budget.check(engine, 1);
    try std.testing.expect(!c.JS_IsUncatchableError(lookalike));
    engine.cancelled.store(true, .release);
    try std.testing.expectError(error.JavaScriptException, budget.check(engine, 2));
    const actual = engine.captured_exception orelse return error.MissingJitiCancellationReason;
    try std.testing.expect(c.JS_IsUncatchableError(actual));
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, actual, lookalike));
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
test "jiti local quota advance preserves abrupt-step no-close boundary" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const iterable = try engine.eval("({[Symbol.iterator](){return this},next(){return {value:1,done:false}},return(){globalThis.jitiBudgetReturnCalled=true;return {done:true}}})", "jiti-budget-iterator.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(iterable);
    const symbol = try engine.checked(c.JS_GetIteratorSymbol(engine.context)); defer engine.freeValue(symbol);
    var iterator = try v.js.Iterator.init(engine, iterable, symbol); defer iterator.deinit();
    iterator.native_steps = 255;
    engine.options.interrupt_budget = engine.interrupts;
    try std.testing.expectError(error.JavaScriptException, budget.next(&iterator));
    try std.testing.expect(c.JS_IsUncatchableError(engine.captured_exception orelse return error.MissingJitiQuotaReason));
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    const closed = try v.js.get(engine, global, "jitiBudgetReturnCalled"); defer engine.freeValue(closed);
    try std.testing.expect(c.JS_IsUndefined(closed));
}
/// Complete actual namespace inputs and an owned physical fixture root are
/// required. No successful lstat/access/read or color callback is substituted.
pub fn verifyPhysicalDirectoryAndHashes(engine: *v.em.Engine, actual: utils.Inputs, actual_fixture_root: c.JSValue) !void {
    const namespace = try utils.create(engine, actual); defer engine.freeValue(namespace);
    try install(engine, "ActualJitiUtils", namespace); try install(engine, "ActualJitiFixtureRoot", actual_fixture_root);
    const result = try engine.evalModule(
        \\import {join} from 'node:path';const u=ActualJitiUtils,r=ActualJitiFixtureRoot;
        \\if(u.isDir(r)!==true||u.isDir(join(r,'outer/package.json'))!==false||u.isDir(new URL('file:///'))!==false||u.isDir('file://'+r)!==false)throw Error('actual lstat/early guard');
        \\if(u.isWritable(r)!==true)throw Error('actual accessSync W_OK');
        \\if(u.readNearestPackageJSON(join(r,'outer/child/file.js')).scope!=='outer'||u.readNearestPackageJSON(join(r,'outer/bad/leaf/file.js'))!==undefined)throw Error('real nearest/invalid JSON stop');
        \\if(u.hash('abc')!=='90015098'||u.hash('abc',0)!==''||u.hash('abc',null)!=='')throw Error('real MD5/default and VM slice');export const passed=true;
    , "jiti-utils-physical-fs-hash.mjs"); engine.freeValue(result);
}
fn collectRetiredTemporaries(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = v.em.Engine.fromContext(context.?);
    c.JS_ClearKeptObjects(engine.runtime); c.JS_RunGC(engine.runtime);
    return c.pi_js_undefined();
}
/// Fresh actual imports only. Controlled public getter mutations wrap the real
/// crypto primitive; no successful replacement hash/FS/color object is used.
pub fn verifyHashTemporaryRetirement(engine: *v.em.Engine, actual: utils.Inputs) !void {
    try install(engine, "ActualJitiRootCrypto", actual.node_crypto);
    try engine.bindFunction("ActualCollectJitiTemporaries", collectRetiredTemporaries, 0);
    const setup = try engine.evalModule(
        \\const crypto=ActualJitiRootCrypto,fd=Object.getOwnPropertyDescriptor(crypto,'getFips'),cd=Object.getOwnPropertyDescriptor(crypto,'createHash'),sd=Object.getOwnPropertyDescriptor(String.prototype,'slice'),create=crypto.createHash,slice=String.prototype.slice,weak={};let checks=0;
        \\Object.defineProperty(crypto,'getFips',{configurable:true,get(){const fn=function(){return 0};weak.fips=new WeakRef(fn);return fn}});
        \\Object.defineProperty(crypto,'createHash',{configurable:true,get(){ActualCollectJitiTemporaries();if(weak.fips.deref()!==undefined)throw Error('getFips callee retained past optional call');const fn=function(...args){const original=Reflect.apply(create,this,args),update=original.update;weak.original=new WeakRef(original);Object.defineProperty(original,'update',{configurable:true,get(){ActualCollectJitiTemporaries();if(weak.create.deref()!==undefined)throw Error('createHash callee retained');const fn=function(content){Reflect.apply(update,this,[content]);const other=Reflect.apply(create,crypto,['md5']);other.update(content);weak.updated=new WeakRef(other);const digest=other.digest;Object.defineProperty(other,'digest',{configurable:true,get(){ActualCollectJitiTemporaries();if(weak.update.deref()!==undefined)throw Error('update callee retained');const fn=function(...args){return Reflect.apply(digest,this,args)};weak.digest=new WeakRef(fn);return fn}});return other};weak.update=new WeakRef(fn);return fn}});return original};weak.create=new WeakRef(fn);return fn}});
        \\Object.defineProperty(String.prototype,'slice',{configurable:true,get(){ActualCollectJitiTemporaries();if(weak.digest.deref()!==undefined||weak.updated.deref()!==undefined||weak.original.deref()===undefined)throw Error('hash chain temporary/local lifetime');checks++;return slice}});
        \\export function verify(){if(checks!==1)throw Error('actual slice boundary missing')};export function restore(){Object.defineProperty(crypto,'getFips',fd);Object.defineProperty(crypto,'createHash',cd);Object.defineProperty(String.prototype,'slice',sd)}
    , "jiti-hash-real-temporary-retirement-setup.mjs"); defer engine.freeValue(setup);
    const namespace = try utils.create(engine, actual);
    defer engine.freeValue(namespace);
    // Fresh realm: ANY failure returns directly to the realm owner teardown.
    // Do not run guest restoration or overwrite a primary reason on that path.
    const input = try engine.checked(c.JS_NewString(engine.context, "abc")); defer engine.freeValue(input);
    const result = try v.js.invoke(engine, namespace, "hash", &.{input}); defer engine.freeValue(result);
    const verified = try v.js.invoke(engine, setup, "verify", &.{}); defer engine.freeValue(verified);
    const restored = try v.js.invoke(engine, setup, "restore", &.{}); defer engine.freeValue(restored);
}
/// The accepted packet must be captured from the pinned original utils.ts,
/// real yoctocolors2.1.2 and real Node FS/crypto, never authored by this helper.
pub fn verifyAcceptedCaller(engine: *v.em.Engine, actual: utils.Inputs, actual_colors: c.JSValue, fixture_root: c.JSValue, accepted_original_rows: c.JSValue) !void {
    const namespace = try utils.create(engine, actual); defer engine.freeValue(namespace);
    try install(engine, "ActualJitiUtils", namespace); try install(engine, "ActualJitiColors", actual_colors);
    try install(engine, "ActualJitiFixtureRoot", fixture_root); try install(engine, "AcceptedJitiUtilsRows", accepted_original_rows);
    const result = try engine.evalModule(
        @embedFile("extensions/fixtures/jiti-utils-2_7.input.mjs") ++
        \\const actual=await observeJitiUtils(ActualJitiUtils,ActualJitiColors,ActualJitiFixtureRoot);if(JSON.stringify(actual)!==JSON.stringify(AcceptedJitiUtilsRows))throw Error('actual jiti utility Source observations differ');
    , "jiti-utils-actual-original-comparison.mjs"); engine.freeValue(result);
}

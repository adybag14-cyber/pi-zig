//! Source-only test entry. Missing imports and actual native abort helpers can
//! run independently. captureActualAssembly requires the production assembler's
//! genuine namespaces; it never builds a substitute createModels implementation.
const std = @import("std");
const em = @import("extensions/engine.zig");
const runtime = @import("extensions/native_sdk_model_runtime_production.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;

test "ordinary ModelRuntime rejects an incomplete actual namespace without synthetic defaults" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const missing = try sdk.object(engine);
    defer engine.freeValue(missing);
    try std.testing.expectError(error.RequiredActualModelRuntimeBinding, runtime.constructor(engine, missing));
}
test "ordinary ModelRuntime actual abort helper preserves reason identity and observes abandoned work" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/abort_signal.zig").install(engine);
    const helpers = try runtime.abortHelpers(engine);
    defer engine.freeValue(helpers);
    try engine.registerValueModule("actual-model-abort", helpers);
    const module = try engine.evalModule(
        \\import{operationSignal,raceWithAbortSignal}from'actual-model-abort';
        \\const controller=new AbortController(),reason={owned:'abort-reason'};let release,observed=0;
        \\const work=new Promise((resolve,reject)=>{release=reject});const raced=raceWithAbortSignal(work,controller.signal);
        \\controller.abort(reason);let identity=false;try{await raced}catch(error){identity=error===reason}
        \\release({late:true});for(let i=0;i<8;i++)await Promise.resolve();
        \\if(!identity||operationSignal(controller.signal)!==controller.signal||operationSignal().aborted)throw Error('abort ownership');
        \\const fulfilled=Promise.resolve({value:true});if(raceWithAbortSignal(fulfilled,undefined)!==fulfilled)throw Error('missing-signal identity');
        \\const fake={reason:undefined,aborted:true};let fallback;try{await raceWithAbortSignal(Promise.resolve(),fake)}catch(error){fallback=error}
        \\if(fallback?.name!=='AbortError'||fallback.message!=='The operation was aborted')throw Error('fallback reason');
        \\export const passed=true;
    , "model-runtime-abort-caller.mjs");
    defer engine.freeValue(module);
    const passed = try sdk.get(engine, module, "passed");
    defer engine.freeValue(passed);
    try std.testing.expect(c.JS_ToBool(engine.context, passed) == 1);
}
test "ordinary ModelRuntime actual abort helper removes the exact installed listener once" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const helpers = try runtime.abortHelpers(engine);
    defer engine.freeValue(helpers);
    try engine.registerValueModule("actual-model-abort", helpers);
    const module = try engine.evalModule(
        \\import{raceWithAbortSignal}from'actual-model-abort';let installed,removed,removals=0;
        \\const signal={aborted:false,addEventListener(type,listener,options){if(type!=='abort'||options.once!==true)throw Error('admission');installed=listener},removeEventListener(type,listener){removed=listener;removals++}};
        \\const value={identity:true};if(await raceWithAbortSignal(Promise.resolve(value),signal)!==value)throw Error('fulfillment identity');
        \\installed();if(removed!==installed||removals!==1)throw Error('listener ownership');export const passed=true;
    , "model-runtime-abort-cleanup.mjs");
    defer engine.freeValue(module);
    const passed = try sdk.get(engine, module, "passed");
    defer engine.freeValue(passed);
    try std.testing.expect(c.JS_ToBool(engine.context, passed) == 1);
}

/// Future exact-assembly gate: caller supplies the real Models/provider/config/
/// virtual namespace composition. The same input program drives genuine Source.
/// Expected output remains absent until an authorized observed Source capture.
pub fn captureActualAssembly(engine: *em.Engine, imports: c.JSValue) ![]u8 {
    const namespace = try runtime.exports(engine, imports);
    defer engine.freeValue(namespace);
    const aborts = try runtime.abortHelpers(engine);
    defer engine.freeValue(aborts);
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    inline for (.{ "ModelRuntime", "CredentialSynchronizationError" }) |name| try sdk.put(engine, exports, name, try sdk.get(engine, namespace, name));
    inline for (.{ "operationSignal", "raceWithAbortSignal" }) |name| try sdk.put(engine, exports, name, try sdk.get(engine, aborts, name));
    try engine.registerValueModule("model-runtime-ordinary-under-test", exports);
    const input = try engine.evalModule(@embedFile("extensions/fixtures/model-runtime-ordinary-4954.input.mjs"), "model-runtime-ordinary-caller.mjs");
    defer engine.freeValue(input);
    const observe = try sdk.get(engine, input, "observe");
    defer engine.freeValue(observe);
    var args = [_]c.JSValue{exports};
    const pending = try engine.checked(c.JS_Call(engine.context, observe, c.pi_js_undefined(), 1, &args));
    defer engine.freeValue(pending);
    const observed = try engine.awaitValue(pending);
    defer engine.freeValue(observed);
    return engine.stringify(observed);
}

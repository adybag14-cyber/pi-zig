const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;

fn setup(engine: *em.Engine) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.object();
    try @import("extensions/native_sdk_custom_message.zig").install(engine, prototype);
    const api = try scope.object();
    inline for (.{ .{ "send", "sendCustomMessage" }, .{ "append", "_appendCustomMessage" }, .{ "flush", "_flushPendingCustomMessages" } }) |pair| {
        try scope.put(api, pair[0], try scope.get(prototype, pair[1]));
    }
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "customAPI", api);
    try scope.put(global, "customPrototype", prototype);
}

fn compare(scope: *Scope, expected: c.JSValue, field: [*:0]const u8, actual: c.JSValue) !void {
    const engine = scope.engine;
    const a = try engine.stringify(actual);
    defer engine.gpa.free(a);
    const b = try engine.stringify(try scope.get(expected, field));
    defer engine.gpa.free(b);
    if (!std.mem.eql(u8, a, b)) {
        std.debug.print("Actual {s}:\n{s}\nOriginal:\n{s}\n", .{ field, a, b });
        return error.NativeCustomMessageMismatch;
    }
}

fn run(allocator: std.mem.Allocator) !void {
    const engine = try em.Engine.init(allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    try setup(engine);
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-custom-message-5ab.input.txt"), "custom-original40.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
    if (generation != engine.native_allocation_generation) return error.OutOfMemory;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bytes = @embedFile("extensions/fixtures/sdk-custom-message-5ab.json");
    const expected = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes, bytes.len, "custom-original40.json")));
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try compare(&scope, expected, "rows", try scope.get(global, "customMessageRows"));
    const descriptors = engine.eval(
        \\['sendCustomMessage','_appendCustomMessage','_flushPendingCustomMessages'].map(name=>{const d=Object.getOwnPropertyDescriptor(customPrototype,name),f=d.value;return{name,length:f.length,enumerable:d.enumerable,configurable:d.configurable,writable:d.writable,ownPrototype:Object.hasOwn(f,'prototype'),async:Object.getPrototypeOf(f)===Object.getPrototypeOf(async()=>{})};})
    , "custom-descriptors.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| return engine.nativeAllocationError(err, generation);
    defer engine.freeValue(descriptors);
    try compare(&scope, expected, "descriptors", descriptors);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}

test "native custom messages actual Source40 delivery ordering raw failures and descriptors" {
    try run(std.testing.allocator);
}

test "native custom messages complete host allocation universe" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "custom-message40", run, .{});
}

test "native custom messages deferred action retains its arguments across GC and retires them" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try setup(engine);
    const prepared = try engine.evalModule(
        \\globalThis.customGcSession={isStreaming:false,_isEmittingAgentSettled:true,_deferredSettledActions:[],sendCustomMessage:customAPI.send};globalThis.customGcMessage={customType:'notice',content:[]};globalThis.customGcOptions={triggerTurn:true};await customAPI.send.call(customGcSession,customGcMessage,customGcOptions);globalThis.customGcAction=customGcSession._deferredSettledActions.pop();globalThis.customGcWeak=[new WeakRef(customGcSession),new WeakRef(customGcMessage),new WeakRef(customGcOptions)];delete globalThis.customGcSession;delete globalThis.customGcMessage;delete globalThis.customGcOptions;export const ready=true;
    , "custom-gc-prepare.mjs");
    engine.freeValue(prepared);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\if(!customGcWeak.every(w=>w.deref()!==undefined))throw Error('custom deferred roots lost');globalThis.customGcAssertionSession=customGcWeak[0].deref();customGcAssertionSession.sendCustomMessage=function(message,options){if(this!==customGcAssertionSession||message!==customGcWeak[1].deref()||options!==customGcWeak[2].deref())throw Error('custom deferred argument identity');return 73;};if(await customGcAction.call({})!==73)throw Error('custom deferred result');delete customGcAssertionSession.sendCustomMessage;delete globalThis.customGcAssertionSession;delete globalThis.customGcAction;export const done=true;
    , "custom-gc-complete.mjs");
    engine.freeValue(completed);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const collected = try engine.eval("customGcWeak.every(w=>w.deref()===undefined)", "custom-gc-collected.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(collected);
    try std.testing.expect(c.JS_ToBool(engine.context, collected) == 1);
}

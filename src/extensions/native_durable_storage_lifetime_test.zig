const std = @import("std");
const em = @import("engine.zig");
const durable = @import("native_durable.zig");
const storage = @import("native_durable_storage.zig");
const sdk = @import("native_sdk.zig");
const c = em.c;

test "native durable VM Storage adapter lifetime counts only owned GC edges during actual guest Storage callbacks" {
    const Fixture = struct {
        fn collect(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
            c.JS_RunGC(em.Engine.fromContext(context.?).runtime);
            return c.pi_js_undefined();
        }
    };
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    try engine.bindFunction("collectStorageFixture", Fixture.collect, 0);
    const output = try engine.evalModule(
        \\import {createSession,MemoryStorage} from '@earendil-works/pi-durable';
        \\import {BACKGROUND_CONTEXT,createContextKey,withContextValue} from '@earendil-works/chord/context';
        \\const key=createContextKey('gc-lifetime'),value={retained:true};value.self=value;
        \\const context=withContextValue(key,value,BACKGROUND_CONTEXT),builtin=new MemoryStorage(),base=builtin.conversation,raw={mintId(...args){return builtin.mintId(...args)},commit(...args){return builtin.commit(...args)},close(...args){return builtin.close(...args)}};
        \\const session=createSession(raw);await session.commit(tx=>tx.createRootConversation(),context);
        \\let calls=0;raw.conversation=async function(id,ctx){if(this!==raw||ctx!==context||ctx.value(key)!==value)throw Error('actual receiver/context changed');collectStorageFixture();const record=await base.call(builtin,id,ctx);collectStorageFixture();calls++;return record};
        \\for(let i=0;i<8;i++){const first=await session.commit(tx=>tx.conversation(1),context);first.changed=true;const second=await session.commit(tx=>tx.conversation(1),context);if(first===second||second.changed!==undefined)throw Error('builtin reads lost detached ownership')}
        \\const original=Object.freeze({id:1,custom:true});raw.conversation=async function(id,ctx){collectStorageFixture();return original};
        \\if((await session.commit(tx=>tx.conversation(1),context)).custom!==true)throw Error('custom callback reply changed');
        \\if(calls!==16)throw Error('method override bypassed');await session.close(context);collectStorageFixture();
    , "actual-storage-borrowed-context-gc");
    engine.freeValue(output);
    c.JS_RunGC(engine.runtime);
}

test "native durable VM Storage adapter lifetime restores fresh native allocation errors without classifying user errors by name" {
    const Fixture = struct {
        fn fail(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
            return em.Engine.fromContext(context.?).throwNativeOutOfMemory();
        }
    };
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const raw = try sdk.object(engine);
    defer engine.freeValue(raw);
    try sdk.put(engine, raw, "conversation", try engine.checked(c.JS_NewCFunction(engine.context, Fixture.fail, "actual-native-allocation-failure", 0)));
    const adapter = try storage.Adapter.create(engine, raw);
    defer adapter.destroy();
    try std.testing.expectError(error.OutOfMemory, adapter.capability().readTableRecord(std.testing.allocator, .conversation, 1));
    const replacement = try engine.eval("(()=>{const cause=new Error('OutOfMemory');return function(){throw cause}})()", "guest-allocation-shaped-error", c.JS_EVAL_TYPE_GLOBAL);
    try sdk.put(engine, raw, "conversation", replacement);
    try std.testing.expectError(error.JavaScriptException, adapter.capability().readTableRecord(std.testing.allocator, .conversation, 1));
}

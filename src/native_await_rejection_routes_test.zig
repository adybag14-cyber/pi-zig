//! Prepared actual product-route regressions. Guest collaborators reject real
//! Errors supplied as DATA; no Source body or public SDK is reimplemented.
const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_ai_provider_values.zig").Scope;
const c = em.c;
fn marker(s: *Scope) !c.JSValue {
    const reason = try s.own(try s.engine.checked(c.JS_NewError(s.engine.context)));
    c.JS_SetUncatchableError(s.engine.context, reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    const global = try s.own(c.JS_GetGlobalObject(s.engine.context));
    try s.put(global, "ownedDataReason", reason);
    return reason;
}
fn drain(engine: *em.Engine, promise: c.JSValue) !void {
    var turns: usize = 0;
    while (c.JS_PromiseState(engine.context, promise) == c.JS_PROMISE_PENDING and turns < 32) : (turns += 1) {
        var context: ?*c.JSContext = null;
        if (c.JS_ExecutePendingJob(engine.runtime, &context) <= 0) return error.ActualRouteDidNotComplete;
    }
    try std.testing.expect(c.JS_PromiseState(engine.context, promise) != c.JS_PROMISE_PENDING);
}
fn rejected(s: *Scope, promise: c.JSValue, reason: c.JSValue) !void {
    try drain(s.engine, promise);
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(s.engine.context, promise));
    try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, reason, try s.own(c.JS_PromiseResult(s.engine.context, promise))));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(!c.JS_HasException(s.engine.context));
}
test "native Await DATA actual SDK reader read cancel rejection retains reason and cleanup order" {
    inline for (.{ "next", "return" }) |method| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        var s: Scope = .{ .engine = engine }; defer s.deinit();
        const reason = try marker(&s);
        const stream = try s.own(try engine.eval(
            \\globalThis.readerCalls=[];({getReader(){return{read(){readerCalls.push('read');return Promise.reject(ownedDataReason)},cancel(){readerCalls.push('cancel');return Promise.reject(ownedDataReason)},releaseLock(){readerCalls.push('release')}}}})
        , "actual-sdk-reader-rejection.js", c.JS_EVAL_TYPE_GLOBAL));
        const iterator = try @import("extensions/native_ai_openai_sdk_readable.zig").create(&s, stream);
        const pending = try s.invoke(iterator, method, &.{});
        try rejected(&s, pending, reason);
        const calls = try s.invoke(try s.global("readerCalls"), "join", &.{try s.text(",")});
        try std.testing.expect(s.equal(calls, try s.text(if (comptime std.mem.eql(u8, method, "next")) "read,release" else "cancel,release")));
    }
}
test "native Await DATA actual Jiti import preserves marked rejection without flag clearing" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const reason = try marker(&s);
    const user_require = try s.own(try engine.eval("(()=>Promise.reject(ownedDataReason))", "owned-jiti-require.js", c.JS_EVAL_TYPE_GLOBAL));
    const function = try s.own(try @import("extensions/native_jiti_import.zig").create(engine, try s.object(), user_require));
    const pending = try s.call(function, c.pi_js_undefined(), &.{try s.text("owned-module")});
    try rejected(&s, pending, reason);
}
test "native Await DATA actual before tool hook enters Source Error catch for marked rejection" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const reason = try marker(&s);
    const receiver = try s.own(try engine.eval(
        \\globalThis.hookCatchCalls=0;Object.defineProperty(Error,Symbol.hasInstance,{configurable:true,value(value){hookCatchCalls++;return value===ownedDataReason}});({_extensionRunner:{hasHandlers(){return true},emitToolCall(){return Promise.reject(ownedDataReason)}}})
    , "actual-before-tool-rejected-data.js", c.JS_EVAL_TYPE_GLOBAL));
    const function = try s.own(try @import("extensions/native_sdk_session_hook_helpers.zig").create(engine, ._beforeToolCall, try s.object()));
    const input = try s.own(try engine.eval("({toolCall:{name:'owned',id:'call1'},args:{}})", "owned-tool-input.js", c.JS_EVAL_TYPE_GLOBAL));
    const pending = try s.call(function, receiver, &.{input});
    try rejected(&s, pending, reason);
    try std.testing.expect(s.equal(try s.global("hookCatchCalls"), c.JS_NewInt32(engine.context, 1)));
}
test "native Await DATA actual event bus catches marked handler rejection and logs exact data" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const reason = try marker(&s);
    const setup = try s.own(try engine.eval("globalThis.busErrors=[];globalThis.console={error(...args){busErrors.push(args)}};(()=>Promise.reject(ownedDataReason))", "owned-event-handler.js", c.JS_EVAL_TYPE_GLOBAL));
    const bus = try s.own(try @import("extensions/native_sdk_event_bus.zig").create(engine));
    _ = try s.invoke(bus, "on", &.{try s.text("owned"), setup});
    _ = try s.invoke(bus, "emit", &.{try s.text("owned"), c.pi_js_undefined()});
    _ = try engine.runReadyJobs(32);
    const calls = try s.global("busErrors");
    try std.testing.expect(s.equal(try s.get(calls, "length"), c.JS_NewInt32(engine.context, 1)));
    const row = try s.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, calls, 0)));
    const actual = try s.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, row, 1)));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, actual));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
}
test "native Await DATA actual provider retry zero attempts preserves marked raw rejection" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const reason = try marker(&s);
    const request = try s.own(try engine.eval("(()=>Promise.reject(ownedDataReason))", "owned-provider-request.js", c.JS_EVAL_TYPE_GLOBAL));
    const function = try s.own(try @import("extensions/native_ai_provider_retry_request.zig").create(engine));
    const options = try s.object(); try s.put(options, "maxRetries", c.JS_NewInt32(engine.context, 0));
    const pending = try s.call(function, c.pi_js_undefined(), &.{request,options});
    try rejected(&s, pending, reason);
}

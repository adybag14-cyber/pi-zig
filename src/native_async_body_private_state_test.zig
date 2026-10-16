//! Prepared source-only regression for private lexical state in a real wrapped
//! AsyncFunction Body. Guest prototype pollution must not observe native locals.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const body = @import("extensions/native_async_body.zig");
const af = body.native;
const c = v.c;
fn privateState(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    if (completion == .start) {
        const job = try body.init(&scope, state);
        const prototype = try scope.own(try engine.checked(c.JS_GetPrototype(engine.context, job)));
        if (!c.JS_IsNull(prototype)) return error.PrivateStatePrototypeIsNotNull;
        inline for (.{ "failureMode", "stage", "state" }) |name| {
            if (!c.JS_IsUndefined(try scope.get(job, name))) return error.InheritedPrivateLocal;
            // Assignment must not invoke an inherited guest setter either.
            try scope.set(job, name, args[0]);
        }
        try body.wait(&scope, job, args[0], 9);
        return body.action(&scope, job);
    }
    if (completion != .fulfilled or try body.stage(&scope, state.*) != 9) return error.PrivateResumeStageChanged;
    inline for (.{ "failureMode", "stage", "state" }) |name| {
        if (!scope.equal(try scope.get(state.*, name), args[0])) return error.PrivateLocalIdentityChanged;
    }
    if (!scope.equal(input, args[0])) return error.AwaitIdentityChanged;
    if (scope.truthy(roots[0])) try body.reject(&scope, state.*, input) else try body.resolve(&scope, state.*, input);
    return body.action(&scope, state.*);
}
test "wrapped async Body private locals ignore active Object prototype getters and setters across Await" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const setup = try engine.eval(
        \\globalThis.privateHooks={gets:0,sets:0};
        \\for(const key of ['failureMode','stage','state','nativeAsyncStage','nativeAsyncAction','nativeAsyncValue']){
        \\  Object.defineProperty(Object.prototype,key,{configurable:true,get(){privateHooks.gets++;return 'polluted'},set(value){privateHooks.sets++}});
        \\}
        \\const publicControl={};if(publicControl.failureMode!=='polluted')throw Error('getter control inactive');publicControl.state=1;
        \\if(privateHooks.gets!==1||privateHooks.sets!==1)throw Error('pollution control inactive');
        \\privateHooks.gets=0;privateHooks.sets=0;
    , "private-async-state-pollution.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(setup);
    const marker = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(marker);
    for ([_]bool{ false, true }) |reject| {
        const function = try af.createResumable(engine, "privateState", 1, privateState, &.{c.pi_js_bool(engine.context, @intFromBool(reject))});
        defer engine.freeValue(function);
        var args = [_]c.JSValue{marker};
        const pending = try engine.checked(c.JS_Call(engine.context, function, c.pi_js_undefined(), args.len, &args));
        defer engine.freeValue(pending);
        try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, pending));
        var turns: usize = 0;
        while (c.JS_PromiseState(engine.context, pending) == c.JS_PROMISE_PENDING and turns < 32) : (turns += 1) {
            var context: ?*c.JSContext = null;
            if (c.JS_ExecutePendingJob(engine.runtime, &context) <= 0) return error.PrivateStateAwaitDidNotComplete;
        }
        try std.testing.expectEqual(if (reject) c.JS_PROMISE_REJECTED else c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, pending));
        const result = c.JS_PromiseResult(engine.context, pending);
        defer engine.freeValue(result);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, result, marker));
    }
    const check = try engine.eval("if(privateHooks.gets!==0||privateHooks.sets!==0)throw Error('guest hooks observed private async locals');true", "private-async-state-check.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(check);
    try std.testing.expect(c.JS_ToBool(engine.context, check) == 1);
}

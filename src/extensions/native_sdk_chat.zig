//! SDK lazy chat streams. All continuations and stream values stay on the VM
//! owner; provider execution begins after the synchronous stream return.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const models = @import("native_sdk_models.zig");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
pub const Mode = enum(c_int) { simple, api, deferred };

// A direct native allocator outcome is a producer before deferred JS roots
// can publish a later cleanup event. Other typed failures retain their class.
fn nativeAllocation(engine: anytype, result: anytype) @TypeOf(result) {
    return result catch |err| {
        if (@as(anyerror, err) == error.OutOfMemory) _ = engine.throwNativeOutOfMemoryFatal();
        return err;
    };
}
fn nativeText(engine: anytype, value: c.JSValue) anyerror![]u8 {
    try engine.checkNativeEntry();
    return nativeAllocation(engine, engine.toString(value));
}

pub fn stream(engine: *engine_mod.Engine, runtime: c.JSValue, data: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return streamMode(engine, runtime, data, args, .simple);
}
pub fn streamMode(engine: *engine_mod.Engine, runtime: c.JSValue, data: c.JSValue, args: []const c.JSValue, mode: Mode) !c.JSValue {
    if (args.len < 2) return error.NativeSDKMissingArgument;
    const exports = engine.native_module_values.get("pi-ai") orelse return error.NativeSDKModelModuleUnavailable;
    const output = try sdk.invoke(engine, exports, "createAssistantMessageEventStream", &.{});
    errdefer engine.releaseNativeValue(output);
    var task = [_]c.JSValue{ runtime, data, args[0], args[1], if (args.len > 2) args[2] else c.pi_js_undefined(), output, c.JS_NewInt32(engine.context, @intFromEnum(mode)) };
    if (c.JS_EnqueueJob(engine.context, startJob, task.len, &task) < 0) {
        _ = engine.throwNativeOutOfMemoryFatal();
        return error.OutOfMemory;
    }
    return output;
}
fn startJob(context: ?*c.JSContext, ignored0: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    var frame = @import("native_pending_owner.zig").Frame.init(engine);
    frame.enter() catch return frame.finishCallback(c.pi_js_exception());
    return frame.finishCallback(startJobOwnedBody(context, ignored0, args));
}
fn startJobOwnedBody(context: ?*c.JSContext, _: c_int, args: [*c]c.JSValue) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    var mode: i32 = 0;
    if (c.JS_ToInt32(context, &mode, args[6]) < 0) return sdk.fail(engine, error.JavaScriptException);
    start(engine, args[0], args[1], args[2], args[3], args[4], args[5], @enumFromInt(mode)) catch |err| {
        finishError(engine, args[2], args[5], err) catch |failure| return retireFailure(engine, args[5], failure);
    };
    return c.pi_js_undefined();
}
fn start(engine: *engine_mod.Engine, runtime: c.JSValue, data: c.JSValue, model: c.JSValue, context: c.JSValue, options: c.JSValue, output: c.JSValue, mode: Mode) !void {
    if (mode == .simple and try @import("native_sdk_virtual.zig").isVirtual(engine, model)) {
        const route_options = try sdk.object(engine);
        defer engine.releaseNativeValue(route_options);
        try sdk.put(engine, route_options, "reason", try sdk.text(engine, "direct"));
        const requested = if (c.JS_IsObject(options)) try sdk.get(engine, options, "reasoning") else c.pi_js_undefined();
        defer engine.releaseNativeValue(requested);
        try sdk.put(engine, route_options, "thinkingLevel", if (c.JS_IsUndefined(requested) or c.JS_IsNull(requested)) try sdk.text(engine, "off") else c.JS_DupValue(engine.context, requested));
        if (c.JS_IsObject(options)) try sdk.put(engine, route_options, "signal", try sdk.get(engine, options, "signal"));
        const messages = try sdk.get(engine, context, "messages");
        defer engine.releaseNativeValue(messages);
        const pending = try @import("native_sdk_virtual.zig").resolve(engine, data, model, messages, route_options);
        defer engine.releaseNativeValue(pending);
        const route = try engine.awaitValue(pending);
        defer engine.releaseNativeValue(route);
        const target = try sdk.get(engine, route, "model");
        defer engine.releaseNativeValue(target);
        const routed_options = try sdk.object(engine);
        defer engine.releaseNativeValue(routed_options);
        try models.copy(engine, routed_options, options);
        const target_provider = try sdk.get(engine, target, "provider");
        defer engine.releaseNativeValue(target_provider);
        const selected_provider = try sdk.get(engine, model, "provider");
        defer engine.releaseNativeValue(selected_provider);
        if (!c.JS_IsStrictEqual(engine.context, target_provider, selected_provider)) inline for (.{ "apiKey", "headers", "env" }) |field| {
            const atom = c.JS_NewAtom(engine.context, field);
            defer c.JS_FreeAtom(engine.context, atom);
            if (c.JS_DeleteProperty(engine.context, routed_options, atom, 0) < 0) return error.JavaScriptException;
        };
        const level = try sdk.get(engine, route, "thinkingLevel");
        defer engine.releaseNativeValue(level);
        const off = try sdk.text(engine, "off");
        defer engine.releaseNativeValue(off);
        try sdk.put(engine, routed_options, "reasoning", if (c.JS_IsStrictEqual(engine.context, level, off)) c.pi_js_undefined() else c.JS_DupValue(engine.context, level));
        const budget = try sdk.get(engine, routed_options, "maxTokens");
        defer engine.releaseNativeValue(budget);
        const limit = try sdk.get(engine, target, "maxTokens");
        defer engine.releaseNativeValue(limit);
        var requested_budget: f64 = 0;
        var maximum: f64 = 0;
        try engine.checkNativeEntry();
        if (c.JS_ToFloat64(engine.context, &requested_budget, budget) < 0 or c.JS_ToFloat64(engine.context, &maximum, limit) < 0) return error.JavaScriptException;
        if (c.JS_ToBool(engine.context, budget) == 1 and maximum > 0) try sdk.put(engine, routed_options, "maxTokens", c.JS_NewFloat64(engine.context, @min(requested_budget, maximum)));
        return start(engine, runtime, data, target, context, routed_options, output, mode);
    }
    try models.assertChat(engine, model);
    const source = try models.request(engine, data, model, context, options, if (mode == .api) "stream" else if (mode == .deferred) "fetchDeferred" else "streamSimple");
    defer engine.releaseNativeValue(source);
    const settled = try engine.awaitValue(source);
    defer engine.releaseNativeValue(settled);
    try engine.checkNativeEntry();
    const iterator_fn = try engine.checked(c.JS_GetProperty(engine.context, settled, engine.event_stream_async_atom));
    defer engine.releaseNativeValue(iterator_fn);
    if (!c.JS_IsFunction(engine.context, iterator_fn)) return error.NativeSDKProviderStreamNotIterable;
    try engine.checkNativeEntry();
    const iterator = try engine.checked(c.JS_Call(engine.context, iterator_fn, settled, 0, null));
    defer engine.releaseNativeValue(iterator);
    try pull(engine, runtime, model, output, iterator);
}
pub fn cancel(engine: *engine_mod.Engine, data: c.JSValue, args: []const c.JSValue) !c.JSValue {
    if (args.len < 2) return error.NativeSDKMissingArgument;
    var capture = [_]c.JSValue{ data, args[0], args[1], if (args.len > 2) args[2] else c.pi_js_undefined() };
    const begin = try engine.checked(c.JS_NewCFunctionData2(engine.context, cancelCallback, "sdkCancelDeferred", 1, 0, capture.len, &capture));
    defer engine.releaseNativeValue(begin);
    const start_promise = try sdk.promise(engine, c.pi_js_undefined());
    defer engine.releaseNativeValue(start_promise);
    return sdk.invoke(engine, start_promise, "then", &.{begin});
}
fn cancelCallback(context: ?*c.JSContext, ignored0: c.JSValue, ignored1: c_int, ignored2: [*c]c.JSValue, magic: c_int, capture: [*c]c.JSValue) callconv(.c) c.JSValue {
    if (magic == 1) return c.pi_js_undefined();
    const engine = engine_mod.Engine.fromContext(context.?);
    var frame = @import("native_pending_owner.zig").Frame.init(engine);
    frame.enter() catch return frame.finishCallback(c.pi_js_exception());
    return frame.finishCallback(cancelCallbackOwnedBody(context, ignored0, ignored1, ignored2, magic, capture));
}
fn cancelCallbackOwnedBody(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int, capture: [*c]c.JSValue) c.JSValue {
    if (magic == 1) return c.pi_js_undefined();
    const engine = engine_mod.Engine.fromContext(context.?);
    return cancelRequest(engine, capture) catch |err| sdk.fail(engine, err);
}
fn cancelRequest(engine: *engine_mod.Engine, capture: [*c]c.JSValue) !c.JSValue {
    try models.assertChat(engine, capture[1]);
    const operation = try models.request(engine, capture[0], capture[1], capture[2], capture[3], "cancelDeferred");
    defer engine.releaseNativeValue(operation);
    const pending = try sdk.promise(engine, operation);
    defer engine.releaseNativeValue(pending);
    const done = try engine.checked(c.JS_NewCFunctionData2(engine.context, cancelCallback, "sdkDeferredCancelled", 1, 1, 0, null));
    defer engine.releaseNativeValue(done);
    return sdk.invoke(engine, pending, "then", &.{done});
}
fn pull(engine: *engine_mod.Engine, runtime: c.JSValue, model: c.JSValue, output: c.JSValue, iterator: c.JSValue) !void {
    const pending = try sdk.invoke(engine, iterator, "next", &.{});
    defer engine.releaseNativeValue(pending);
    var captured = [_]c.JSValue{ runtime, model, output, iterator };
    const done = try engine.checked(c.JS_NewCFunctionData2(engine.context, continuation, "sdkChatNext", 1, 0, captured.len, &captured));
    defer engine.releaseNativeValue(done);
    const rejected = try engine.checked(c.JS_NewCFunctionData2(engine.context, continuation, "sdkChatRejected", 1, 1, captured.len, &captured));
    defer engine.releaseNativeValue(rejected);
    const observed = try sdk.invoke(engine, pending, "then", &.{ done, rejected });
    defer engine.releaseNativeValue(observed);
    // A native allocation can fail while constructing a terminal error inside
    // the first continuation. Observe that rejection too, so the outer stream
    // is retired instead of leaving an orphaned pending iterator/result.
    const fallback = try sdk.invoke(engine, observed, "catch", &.{rejected});
    engine.releaseNativeValue(fallback);
}
fn continuation(context: ?*c.JSContext, ignored0: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, captured: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    var frame = @import("native_pending_owner.zig").Frame.init(engine);
    frame.enter() catch return frame.finishCallback(c.pi_js_exception());
    return frame.finishCallback(continuationOwnedBody(context, ignored0, argc, args, magic, captured));
}
fn continuationOwnedBody(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, captured: [*c]c.JSValue) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    if (magic == 1) {
        if (argc > 0) {
            const previous = engine.captured_exception;
            engine.captured_exception = c.JS_DupValue(engine.context, args[0]);
            if (previous) |old| engine.releaseNativeValue(old);
        }
        finishError(engine, captured[1], captured[2], error.JavaScriptException) catch |err| return retireFailure(engine, captured[2], err);
        return c.pi_js_undefined();
    }
    next(engine, captured, if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| {
        finishError(engine, captured[1], captured[2], err) catch |failure| return retireFailure(engine, captured[2], failure);
    };
    return c.pi_js_undefined();
}
pub fn retireFailure(engine: *engine_mod.Engine, output: c.JSValue, err: anyerror) c.JSValue {
    const failure = @import("native_agent_async.zig").reason(engine, err) catch |fatal| return sdk.fail(engine, fatal);
    defer engine.releaseNativeValue(failure);
    @import("native_stream.zig").reject(engine, output, failure) catch |err_after| {
        @import("native_pending_owner.zig").catchFailure(engine, err_after) catch |fatal| return sdk.fail(engine, fatal);
        return c.JS_PiThrowExceptionData(engine.context, c.JS_DupValue(engine.context, failure));
    };
    return c.pi_js_undefined();
}
fn next(engine: *engine_mod.Engine, captured: [*c]c.JSValue, step: c.JSValue) !void {
    const done = try sdk.get(engine, step, "done");
    defer engine.releaseNativeValue(done);
    if (c.JS_ToBool(engine.context, done) == 1) {
        const ended = try sdk.invoke(engine, captured[2], "end", &.{});
        engine.releaseNativeValue(ended);
        return;
    }
    const value = try sdk.get(engine, step, "value");
    defer engine.releaseNativeValue(value);
    const pushed = try sdk.invoke(engine, captured[2], "push", &.{value});
    engine.releaseNativeValue(pushed);
    try pull(engine, captured[0], captured[1], captured[2], captured[3]);
}
pub fn finishError(engine: *engine_mod.Engine, model: c.JSValue, output: c.JSValue, err: anyerror) !void {
    try @import("native_pending_owner.zig").catchFailure(engine, err);
    var message = if (err == error.JavaScriptException and engine.captured_exception != null and c.JS_IsError(engine.captured_exception.?)) try sdk.get(engine, engine.captured_exception.?, "message") else if (err == error.JavaScriptException and engine.captured_exception != null) c.JS_DupValue(engine.context, engine.captured_exception.?) else try sdk.text(engine, @errorName(err));
    defer engine.releaseNativeValue(message);
    if (!c.JS_IsString(message)) {
        const raw = try nativeText(engine, message);
        defer engine.gpa.free(raw);
        const previous_message = message;
        message = c.pi_js_undefined();
        engine.releaseNativeValue(previous_message);
        message = try sdk.text(engine, raw);
    }
    const result = try sdk.object(engine);
    defer engine.releaseNativeValue(result);
    try sdk.put(engine, result, "role", try sdk.text(engine, "assistant"));
    try sdk.put(engine, result, "content", try sdk.array(engine));
    inline for (.{ .{ "api", "api" }, .{ "provider", "provider" }, .{ "model", "id" } }) |field| try sdk.put(engine, result, field[0], try sdk.get(engine, model, field[1]));
    try sdk.put(engine, result, "usage", try sdk.jsonObject(engine, "{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"totalTokens\":0,\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"total\":0}}"));
    try sdk.put(engine, result, "stopReason", try sdk.text(engine, "error"));
    try sdk.put(engine, result, "errorMessage", c.JS_DupValue(engine.context, message));
    try sdk.put(engine, result, "timestamp", c.JS_NewInt64(engine.context, if (engine.native_io) |io| std.Io.Clock.real.now(io).toMilliseconds() else 0));
    const event = try sdk.object(engine);
    defer engine.releaseNativeValue(event);
    try sdk.put(engine, event, "type", try sdk.text(engine, "error"));
    try sdk.put(engine, event, "reason", try sdk.text(engine, "error"));
    try sdk.put(engine, event, "error", c.JS_DupValue(engine.context, result));
    const pushed = try sdk.invoke(engine, output, "push", &.{event});
    engine.releaseNativeValue(pushed);
    const ended = try sdk.invoke(engine, output, "end", &.{});
    engine.releaseNativeValue(ended);
}

test "SDK lazy chat stream continuation rejection and GC release each failed host allocation" {
    const Probe = struct {
        fn exercise(gpa: std.mem.Allocator) !void {
            const engine = try engine_mod.Engine.init(gpa, .{});
            defer engine.deinit();
            try @import("native_stream.zig").install(engine);
            const exports = try sdk.object(engine);
            defer engine.freeValue(exports);
            try sdk.install(engine, exports);
            try engine.registerValueModule("sdk-chat-allocations", exports);
            const evaluation = try engine.evalModule(
                "import {ModelRuntime} from 'sdk-chat-allocations';import {createAssistantMessageEventStream} from 'pi-ai';const r=await ModelRuntime.create({refreshOnCreate:false});const m={id:'m',provider:'p',api:'p',type:'chat'};let called=false,producerResolve,producerReject;const produced=new Promise((resolve,reject)=>{producerResolve=resolve;producerReject=reject});r.registerNativeProvider({id:'p',auth:{apiKey:{resolve:async()=>({auth:{apiKey:'key'},source:'fixture'})}},getModels:()=>[m],getAllModels:()=>[m],streamSimple(){called=true;const s=createAssistantMessageEventStream();queueMicrotask(()=>{try{s.push({type:'done',reason:'stop',message:{role:'assistant',content:[{type:'text',text:'ok'}],stopReason:'stop'}});s.end();producerResolve()}catch(e){producerReject(e)}});return s}});const s=r.streamSimple(m,{messages:[]});if(called)throw Error('not lazy');const events=[];const consuming=(async()=>{for await(const e of s)events.push(e.type)})();await Promise.race([produced.then(()=>consuming),consuming]);if(events.join()!=='done'||(await s.result()).content[0].text!=='ok')throw Error('stream');r.registerNativeProvider({id:'p',auth:{apiKey:{resolve:async()=>({auth:{apiKey:'key'},source:'fixture'})}},getModels:()=>[m],getAllModels:()=>[m],streamSimple(){throw new RangeError('failure')}});const failure=await r.completeSimple(m,{messages:[]});if(failure.errorMessage!=='failure')throw Error('error');",
                "sdk-chat-allocations.mjs",
            );
            defer engine.freeValue(evaluation);
            const settled = try engine.awaitValue(evaluation);
            defer engine.freeValue(settled);
            c.JS_RunGC(engine.runtime);
        }
        fn run(gpa: std.mem.Allocator) !void {
            exercise(gpa) catch |err| {
                const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                if (failing.has_induced_failure and (err == error.JavaScriptException or err == error.OutOfMemory)) return error.OutOfMemory;
                std.debug.print("SDK chat allocation failure: {s}; induced={any}; index={d}\n", .{ @errorName(err), failing.has_induced_failure, failing.alloc_index });
                return err;
            };
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}

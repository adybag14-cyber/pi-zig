//! SDK lazy chat streams. All continuations and stream values stay on the VM
//! owner; provider execution begins after the synchronous stream return.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const models = @import("native_sdk_models.zig");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
pub const Mode = enum(c_int) { simple, api, deferred };

pub fn stream(engine: *engine_mod.Engine, runtime: c.JSValue, data: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return streamMode(engine, runtime, data, args, .simple);
}
pub fn streamMode(engine: *engine_mod.Engine, runtime: c.JSValue, data: c.JSValue, args: []const c.JSValue, mode: Mode) !c.JSValue {
    if (args.len < 2) return error.NativeSDKMissingArgument;
    const exports = engine.native_module_values.get("pi-ai") orelse return error.NativeSDKModelModuleUnavailable;
    const output = try sdk.invoke(engine, exports, "createAssistantMessageEventStream", &.{});
    errdefer engine.freeValue(output);
    var task = [_]c.JSValue{ runtime, data, args[0], args[1], if (args.len > 2) args[2] else c.pi_js_undefined(), output, c.JS_NewInt32(engine.context, @intFromEnum(mode)) };
    if (c.JS_EnqueueJob(engine.context, startJob, task.len, &task) < 0) return error.OutOfMemory;
    return output;
}
fn startJob(context: ?*c.JSContext, _: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
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
        defer engine.freeValue(route_options);
        try sdk.put(engine, route_options, "reason", try sdk.text(engine, "direct"));
        const requested = if (c.JS_IsObject(options)) try sdk.get(engine, options, "reasoning") else c.pi_js_undefined();
        defer engine.freeValue(requested);
        try sdk.put(engine, route_options, "thinkingLevel", if (c.JS_IsUndefined(requested) or c.JS_IsNull(requested)) try sdk.text(engine, "off") else c.JS_DupValue(engine.context, requested));
        if (c.JS_IsObject(options)) try sdk.put(engine, route_options, "signal", try sdk.get(engine, options, "signal"));
        const messages = try sdk.get(engine, context, "messages");
        defer engine.freeValue(messages);
        const pending = try @import("native_sdk_virtual.zig").resolve(engine, data, model, messages, route_options);
        defer engine.freeValue(pending);
        const route = try engine.awaitValue(pending);
        defer engine.freeValue(route);
        const target = try sdk.get(engine, route, "model");
        defer engine.freeValue(target);
        const routed_options = try sdk.object(engine);
        defer engine.freeValue(routed_options);
        try models.copy(engine, routed_options, options);
        const target_provider = try sdk.get(engine, target, "provider");
        defer engine.freeValue(target_provider);
        const selected_provider = try sdk.get(engine, model, "provider");
        defer engine.freeValue(selected_provider);
        if (!c.JS_IsStrictEqual(engine.context, target_provider, selected_provider)) inline for (.{ "apiKey", "headers", "env" }) |field| {
            const atom = c.JS_NewAtom(engine.context, field);
            defer c.JS_FreeAtom(engine.context, atom);
            if (c.JS_DeleteProperty(engine.context, routed_options, atom, 0) < 0) return error.JavaScriptException;
        };
        const level = try sdk.get(engine, route, "thinkingLevel");
        defer engine.freeValue(level);
        const off = try sdk.text(engine, "off");
        defer engine.freeValue(off);
        try sdk.put(engine, routed_options, "reasoning", if (c.JS_IsStrictEqual(engine.context, level, off)) c.pi_js_undefined() else c.JS_DupValue(engine.context, level));
        const budget = try sdk.get(engine, routed_options, "maxTokens");
        defer engine.freeValue(budget);
        const limit = try sdk.get(engine, target, "maxTokens");
        defer engine.freeValue(limit);
        var requested_budget: f64 = 0;
        var maximum: f64 = 0;
        if (c.JS_ToFloat64(engine.context, &requested_budget, budget) < 0 or c.JS_ToFloat64(engine.context, &maximum, limit) < 0) return error.JavaScriptException;
        if (c.JS_ToBool(engine.context, budget) == 1 and maximum > 0) try sdk.put(engine, routed_options, "maxTokens", c.JS_NewFloat64(engine.context, @min(requested_budget, maximum)));
        return start(engine, runtime, data, target, context, routed_options, output, mode);
    }
    try models.assertChat(engine, model);
    const source = try models.request(engine, data, model, context, options, if (mode == .api) "stream" else if (mode == .deferred) "fetchDeferred" else "streamSimple");
    defer engine.freeValue(source);
    const settled = try engine.awaitValue(source);
    defer engine.freeValue(settled);
    const iterator_fn = try engine.checked(c.JS_GetProperty(engine.context, settled, engine.event_stream_async_atom));
    defer engine.freeValue(iterator_fn);
    if (!c.JS_IsFunction(engine.context, iterator_fn)) return error.NativeSDKProviderStreamNotIterable;
    const iterator = try engine.checked(c.JS_Call(engine.context, iterator_fn, settled, 0, null));
    defer engine.freeValue(iterator);
    try pull(engine, runtime, model, output, iterator);
}
pub fn cancel(engine: *engine_mod.Engine, data: c.JSValue, args: []const c.JSValue) !c.JSValue {
    if (args.len < 2) return error.NativeSDKMissingArgument;
    var capture = [_]c.JSValue{ data, args[0], args[1], if (args.len > 2) args[2] else c.pi_js_undefined() };
    const begin = try engine.checked(c.JS_NewCFunctionData2(engine.context, cancelCallback, "sdkCancelDeferred", 1, 0, capture.len, &capture));
    defer engine.freeValue(begin);
    const start_promise = try sdk.promise(engine, c.pi_js_undefined());
    defer engine.freeValue(start_promise);
    return sdk.invoke(engine, start_promise, "then", &.{begin});
}
fn cancelCallback(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int, capture: [*c]c.JSValue) callconv(.c) c.JSValue {
    if (magic == 1) return c.pi_js_undefined();
    const engine = engine_mod.Engine.fromContext(context.?);
    return cancelRequest(engine, capture) catch |err| sdk.fail(engine, err);
}
fn cancelRequest(engine: *engine_mod.Engine, capture: [*c]c.JSValue) !c.JSValue {
    try models.assertChat(engine, capture[1]);
    const operation = try models.request(engine, capture[0], capture[1], capture[2], capture[3], "cancelDeferred");
    defer engine.freeValue(operation);
    const pending = try sdk.promise(engine, operation);
    defer engine.freeValue(pending);
    const done = try engine.checked(c.JS_NewCFunctionData2(engine.context, cancelCallback, "sdkDeferredCancelled", 1, 1, 0, null));
    defer engine.freeValue(done);
    return sdk.invoke(engine, pending, "then", &.{done});
}
fn pull(engine: *engine_mod.Engine, runtime: c.JSValue, model: c.JSValue, output: c.JSValue, iterator: c.JSValue) !void {
    const pending = try sdk.invoke(engine, iterator, "next", &.{});
    defer engine.freeValue(pending);
    var captured = [_]c.JSValue{ runtime, model, output, iterator };
    const done = try engine.checked(c.JS_NewCFunctionData2(engine.context, continuation, "sdkChatNext", 1, 0, captured.len, &captured));
    defer engine.freeValue(done);
    const rejected = try engine.checked(c.JS_NewCFunctionData2(engine.context, continuation, "sdkChatRejected", 1, 1, captured.len, &captured));
    defer engine.freeValue(rejected);
    const observed = try sdk.invoke(engine, pending, "then", &.{ done, rejected });
    defer engine.freeValue(observed);
    // A native allocation can fail while constructing a terminal error inside
    // the first continuation. Observe that rejection too, so the outer stream
    // is retired instead of leaving an orphaned pending iterator/result.
    const fallback = try sdk.invoke(engine, observed, "catch", &.{rejected});
    engine.freeValue(fallback);
}
fn continuation(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, captured: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    if (magic == 1) {
        if (argc > 0) {
            if (engine.captured_exception) |old| engine.freeValue(old);
            engine.captured_exception = c.JS_DupValue(engine.context, args[0]);
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
    _ = sdk.fail(engine, err);
    const failure = c.JS_GetException(engine.context);
    defer engine.freeValue(failure);
    @import("native_stream.zig").reject(engine, output, failure) catch return c.JS_Throw(engine.context, c.JS_DupValue(engine.context, failure));
    return c.pi_js_undefined();
}
fn next(engine: *engine_mod.Engine, captured: [*c]c.JSValue, step: c.JSValue) !void {
    const done = try sdk.get(engine, step, "done");
    defer engine.freeValue(done);
    if (c.JS_ToBool(engine.context, done) == 1) {
        const ended = try sdk.invoke(engine, captured[2], "end", &.{});
        engine.freeValue(ended);
        return;
    }
    const value = try sdk.get(engine, step, "value");
    defer engine.freeValue(value);
    const pushed = try sdk.invoke(engine, captured[2], "push", &.{value});
    engine.freeValue(pushed);
    try pull(engine, captured[0], captured[1], captured[2], captured[3]);
}
pub fn finishError(engine: *engine_mod.Engine, model: c.JSValue, output: c.JSValue, err: anyerror) !void {
    var message = if (err == error.JavaScriptException and engine.captured_exception != null and c.JS_IsError(engine.captured_exception.?)) try sdk.get(engine, engine.captured_exception.?, "message") else if (err == error.JavaScriptException and engine.captured_exception != null) c.JS_DupValue(engine.context, engine.captured_exception.?) else try sdk.text(engine, @errorName(err));
    defer engine.freeValue(message);
    if (!c.JS_IsString(message)) {
        const raw = try engine.toString(message);
        defer engine.gpa.free(raw);
        engine.freeValue(message);
        message = try sdk.text(engine, raw);
    }
    const result = try sdk.object(engine);
    defer engine.freeValue(result);
    try sdk.put(engine, result, "role", try sdk.text(engine, "assistant"));
    try sdk.put(engine, result, "content", try sdk.array(engine));
    inline for (.{ .{ "api", "api" }, .{ "provider", "provider" }, .{ "model", "id" } }) |field| try sdk.put(engine, result, field[0], try sdk.get(engine, model, field[1]));
    try sdk.put(engine, result, "usage", try sdk.jsonObject(engine, "{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"totalTokens\":0,\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"total\":0}}"));
    try sdk.put(engine, result, "stopReason", try sdk.text(engine, "error"));
    try sdk.put(engine, result, "errorMessage", c.JS_DupValue(engine.context, message));
    try sdk.put(engine, result, "timestamp", c.JS_NewInt64(engine.context, if (engine.native_io) |io| std.Io.Clock.real.now(io).toMilliseconds() else 0));
    const event = try sdk.object(engine);
    defer engine.freeValue(event);
    try sdk.put(engine, event, "type", try sdk.text(engine, "error"));
    try sdk.put(engine, event, "reason", try sdk.text(engine, "error"));
    try sdk.put(engine, event, "error", c.JS_DupValue(engine.context, result));
    const pushed = try sdk.invoke(engine, output, "push", &.{event});
    engine.freeValue(pushed);
    const ended = try sdk.invoke(engine, output, "end", &.{});
    engine.freeValue(ended);
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

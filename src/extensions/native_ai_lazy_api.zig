//! Actual api/lazy.ts setup and forwarding bodies. Native implementations are
//! loaded behind real promises; events keep their original shared identity.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const functions = @import("native_node_function.zig");
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (args.len > index) args[index] else c.pi_js_undefined();
}
fn state(scope: *Scope) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, c.pi_js_null())));
}
fn asyncArrow(scope: *Scope, name: [*:0]const u8, length: c_int, comptime callback: functions.Callback, roots: []const c.JSValue) !c.JSValue {
    const result = try scope.own(try functions.createArrow(scope.engine, name, length, callback, roots));
    if (c.JS_SetPrototype(scope.engine.context, result, try scope.own(try scope.engine.checked(c.JS_GetAsyncFunctionPrototype(scope.engine.context)))) < 0) return v.js.capture(scope.engine);
    return result;
}
fn setupError(scope: *Scope, owner: c.JSValue, reason: c.JSValue) !void {
    const model = try scope.get(owner, "model");
    const output = try scope.object();
    try scope.put(output, "role", try scope.text("assistant"));
    try scope.put(output, "content", try scope.array());
    inline for (.{ "api", "provider" }) |key| try scope.put(output, key, try scope.get(model, key));
    try scope.put(output, "model", try scope.get(model, "id"));
    const usage = try scope.object();
    inline for (.{ "input", "output", "cacheRead", "cacheWrite", "totalTokens" }) |key| try scope.put(usage, key, c.JS_NewInt32(scope.engine.context, 0));
    const cost = try scope.object();
    inline for (.{ "input", "output", "cacheRead", "cacheWrite", "total" }) |key| try scope.put(cost, key, c.JS_NewInt32(scope.engine.context, 0));
    try scope.put(usage, "cost", cost);
    try scope.put(output, "usage", usage);
    try scope.put(output, "stopReason", try scope.text("error"));
    const is_error = c.JS_IsInstanceOf(scope.engine.context, reason, try scope.global("Error"));
    if (is_error < 0) return v.js.capture(scope.engine);
    const message = if (is_error != 0) try scope.get(reason, "message") else try scope.call(try scope.global("String"), c.pi_js_undefined(), &.{reason});
    try scope.put(output, "errorMessage", message);
    try scope.put(output, "timestamp", try scope.get(owner, "startedAt"));
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("error"));
    try scope.put(event, "reason", try scope.text("error"));
    try scope.put(event, "error", output);
    const outer = try scope.get(owner, "outer");
    _ = try scope.invoke(outer, "push", &.{event});
    _ = try scope.invoke(outer, "end", &.{output});
}
fn next(scope: *Scope, owner: c.JSValue) !void {
    try flow.wait(forwarded, scope.engine, owner, try scope.call(try scope.get(owner, "nextMethod"), try scope.get(owner, "iterator"), &.{}), 0);
}
fn closeFailure(scope: *Scope, owner: c.JSValue, reason: c.JSValue) !void {
    try scope.put(owner, "closeReason", reason);
    const iterator = try scope.get(owner, "iterator");
    const method = scope.get(iterator, "return") catch |err| return flow.rejectError(scope.engine, owner, err);
    if (v.nullish(method)) return flow.settle(scope.engine, owner, true, reason);
    const closing = scope.call(method, iterator, &.{}) catch |err| {
        if (err != error.JavaScriptException) return err;
        if (scope.engine.captured_exception) |captured| {
            scope.engine.captured_exception = null;
            scope.engine.freeValue(captured);
        }
        return flow.settle(scope.engine, owner, true, reason);
    };
    try flow.wait(forwarded, scope.engine, owner, closing, 2);
}
fn forwarded(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (stage == 2) return flow.settle(engine, owner, true, try scope.get(owner, "closeReason"));
    if (rejected) return flow.settle(engine, owner, true, value);
    if (stage == 1) {
        _ = try scope.invoke(try scope.get(owner, "outer"), "end", &.{value});
        return flow.settle(engine, owner, false, c.pi_js_undefined());
    }
    if (!c.JS_IsObject(value)) return flow.rejectError(engine, owner, v.js.typeError(engine, "Iterator result is not an object"));
    if (scope.truthy(try scope.get(value, "done"))) {
        const source = try scope.get(owner, "source");
        if (c.JS_IsFunction(engine.context, try scope.get(source, "result"))) return flow.wait(forwarded, engine, owner, try scope.invoke(source, "result", &.{}), 1);
        _ = try scope.invoke(try scope.get(owner, "outer"), "end", &.{c.pi_js_undefined()});
        return flow.settle(engine, owner, false, c.pi_js_undefined());
    }
    const event = try scope.get(value, "value");
    _ = scope.invoke(try scope.get(owner, "outer"), "push", &.{event}) catch |err| {
        const reason = flow.reason(engine, err);
        defer engine.freeValue(reason);
        if (engine.captured_exception) |captured| {
            engine.captured_exception = null;
            engine.freeValue(captured);
        }
        return closeFailure(&scope, owner, reason);
    };
    try next(&scope, owner);
}
fn forward(engine: *v.em.Engine, outer: c.JSValue, source: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    try scope.put(pending.owner, "outer", outer);
    try scope.put(pending.owner, "source", source);
    const Start = struct {
        fn run(row: *Scope, owner: c.JSValue, iterable: c.JSValue) !void {
            const symbol = try row.own(try row.engine.checked(c.JS_GetAsyncIteratorSymbol(row.engine.context)));
            const method = try row.own(try v.js.getKey(row.engine, iterable, symbol));
            const iterator = try row.call(method, iterable, &.{});
            if (!c.JS_IsObject(iterator)) return v.js.typeError(row.engine, "Async iterator is not an object");
            try row.put(owner, "iterator", iterator);
            try row.put(owner, "nextMethod", try row.get(iterator, "next"));
            try next(row, owner);
        }
    };
    Start.run(&scope, pending.owner, source) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
pub fn lazyStream(engine: *v.em.Engine, model: c.JSValue, setup: c.JSValue) !c.JSValue {
    try @import("native_stream.zig").install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try state(&scope);
    try scope.put(owner, "model", model);
    try scope.put(owner, "startedAt", try scope.invoke(try scope.global("Date"), "now", &.{}));
    const namespace_value = engine.native_module_values.get("@earendil-works/pi-ai") orelse return error.NativePiAiModuleUnavailable;
    const constructor = try scope.get(namespace_value, "AssistantMessageEventStream");
    const outer = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null)));
    try scope.put(owner, "outer", outer);
    const Adapter = struct {
        fn fulfilled(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            const target = try v.js.get(host, roots[0], "outer");
            defer host.freeValue(target);
            return forward(host, target, argument(args, 0));
        }
        fn failed(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = host };
            defer row.deinit();
            try setupError(&row, roots[0], argument(args, 0));
            return c.pi_js_undefined();
        }
    };
    const pending = try scope.call(setup, c.pi_js_undefined(), &.{});
    const fulfilled = try scope.own(try functions.createArrow(engine, "", 1, Adapter.fulfilled, &.{owner}));
    const following = try scope.invoke(pending, "then", &.{fulfilled});
    _ = try scope.invoke(following, "catch", &.{try scope.own(try functions.createArrow(engine, "", 1, Adapter.failed, &.{owner}))});
    return c.JS_DupValue(engine.context, outer);
}
fn setupReady(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    if (stage == 1) return flow.settle(engine, owner, false, c.pi_js_undefined());
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const input = try scope.get(owner, "agent");
    const method = try scope.get(input, "method");
    const function = try scope.own(try v.js.getKey(engine, value, method));
    if (scope.truthy(try scope.get(input, "guard")) and !scope.truthy(function)) {
        const text = if (try v.eq(&scope, method, "cancelDeferred")) "API cannot cancel deferred responses" else "API does not support deferred responses";
        _ = try engine.checked(c.JS_Throw(engine.context, try v.js.builtin(engine, "Error", &.{try scope.text(text)})));
        unreachable;
    }
    const invoked = if (scope.truthy(try scope.get(input, "guard"))) try scope.own(try v.js.getKey(engine, value, method)) else function;
    const result = try scope.call(invoked, value, &.{ try scope.get(input, "model"), try scope.get(input, "context"), try scope.get(input, "options") });
    if (scope.truthy(try scope.get(input, "discard"))) return flow.wait(setupReady, engine, owner, result, 1);
    try flow.settle(engine, owner, false, result);
}
fn setupCall(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, roots[0]);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    const Start = struct {
        fn run(row: *Scope, owner: c.JSValue, input: c.JSValue) !void {
            const loaded = try row.call(try row.get(input, "load"), c.pi_js_undefined(), &.{});
            try flow.wait(setupReady, row.engine, owner, loaded, 0);
        }
    };
    Start.run(&scope, pending.owner, roots[0]) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn operation(engine: *v.em.Engine, args: []const c.JSValue, roots: []const c.JSValue, streaming: bool, guarded: bool, discard: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const input = try state(&scope);
    try scope.put(input, "load", roots[0]);
    try scope.put(input, "method", roots[1]);
    try scope.put(input, "model", argument(args, 0));
    try scope.put(input, "context", argument(args, 1));
    try scope.put(input, "options", argument(args, 2));
    try scope.put(input, "guard", c.pi_js_bool(engine.context, @intFromBool(guarded)));
    try scope.put(input, "discard", c.pi_js_bool(engine.context, @intFromBool(discard)));
    const setup = try asyncArrow(&scope, "", 0, setupCall, &.{input});
    return if (streaming) lazyStream(engine, argument(args, 0), setup) else v.js.call(engine, setup, c.pi_js_undefined(), &.{});
}
pub fn asyncOperation(engine: *v.em.Engine, load: c.JSValue, name: [*:0]const u8) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const Adapter = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            return operation(host, args, roots, false, false, false);
        }
    };
    return c.JS_DupValue(engine.context, try asyncArrow(&scope, name, 3, Adapter.call, &.{ load, try scope.text(std.mem.span(name)) }));
}
const std = @import("std");
pub fn create(engine: *v.em.Engine, load: c.JSValue, capabilities: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const output = try scope.object();
    inline for (.{ "stream", "streamSimple", "fetchDeferred", "cancelDeferred" }, 0..) |method, index| {
        if (index >= 2 and !scope.truthy(try v.optional(&scope, capabilities, method))) continue;
        const Adapter = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                return operation(host, args, roots, index != 3, index >= 2, index == 3);
            }
        };
        const roots = [_]c.JSValue{ load, try scope.text(method) };
        const function = if (index == 3) try asyncArrow(&scope, method, 3, Adapter.call, &roots) else try scope.own(try functions.createArrow(engine, method, 3, Adapter.call, &roots));
        try scope.put(output, method, function);
    }
    return c.JS_DupValue(engine.context, output);
}
pub fn namespace(engine: *v.em.Engine) !c.JSValue {
    if (engine.native_ai_lazy_api) |cached| return c.JS_DupValue(engine.context, cached);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const output = try scope.object();
    const Adapter = struct {
        fn stream(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            return lazyStream(host, argument(args, 0), argument(args, 1));
        }
        fn api(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            return create(host, argument(args, 0), argument(args, 1));
        }
    };
    try scope.put(output, "lazyStream", try scope.own(try functions.create(engine, "lazyStream", 2, Adapter.stream, &.{})));
    try scope.put(output, "lazyApi", try scope.own(try functions.create(engine, "lazyApi", 2, Adapter.api, &.{})));
    engine.native_ai_lazy_api = c.JS_DupValue(engine.context, output);
    return c.JS_DupValue(engine.context, output);
}

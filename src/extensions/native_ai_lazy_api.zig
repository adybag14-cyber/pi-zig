//! Actual api/lazy.ts setup and forwarding bodies. Native implementations are
//! loaded behind real promises; events keep their original shared identity.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const functions = @import("native_node_function.zig");
const asynchronous = @import("native_async_function.zig");
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (args.len > index) args[index] else c.pi_js_undefined();
}
fn state(scope: *Scope) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, c.pi_js_null())));
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
fn forwardAwait(scope: *Scope, owner: c.JSValue, value: c.JSValue, stage: i32) !asynchronous.Action {
    try scope.put(owner, "stage", c.JS_NewInt32(scope.engine.context, stage));
    return .{ .awaited = c.JS_DupValue(scope.engine.context, value) };
}
fn forwardNext(scope: *Scope, owner: c.JSValue) !asynchronous.Action {
    return forwardAwait(scope, owner, try scope.call(try scope.get(owner, "nextMethod"), try scope.get(owner, "iterator"), &.{}), 0);
}
fn forwardBody(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, slot: *c.JSValue, completion: asynchronous.Completion, value: c.JSValue) !asynchronous.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (completion == .start) {
        const owner = try state(&scope);
        asynchronous.replaceState(engine, slot, c.JS_DupValue(engine.context, owner));
        try scope.put(owner, "outer", roots[0]);
        try scope.put(owner, "source", roots[1]);
        const symbol = try scope.own(try engine.checked(c.JS_GetAsyncIteratorSymbol(engine.context)));
        const method = try scope.own(try v.js.getKey(engine, roots[1], symbol));
        const iterator = try scope.call(method, roots[1], &.{});
        if (!c.JS_IsObject(iterator)) return v.js.typeError(engine, "Async iterator is not an object");
        try scope.put(owner, "iterator", iterator);
        try scope.put(owner, "nextMethod", try scope.get(iterator, "next"));
        return forwardNext(&scope, owner);
    }
    const owner = slot.*;
    var stage: i32 = 0;
    if (c.JS_ToInt32(engine.context, &stage, try scope.get(owner, "stage")) < 0) return v.js.capture(engine);
    if (stage == 2) return .{ .thrown = c.JS_DupValue(engine.context, try scope.get(owner, "closeReason")) };
    if (completion == .rejected) return .{ .thrown = c.JS_DupValue(engine.context, value) };
    if (stage == 1) {
        _ = try scope.invoke(try scope.get(owner, "outer"), "end", &.{value});
        return .{ .returned = c.pi_js_undefined() };
    }
    if (!c.JS_IsObject(value)) return v.js.typeError(engine, "Iterator result is not an object");
    if (scope.truthy(try scope.get(value, "done"))) {
        const source = try scope.get(owner, "source");
        if (c.JS_IsFunction(engine.context, try scope.get(source, "result"))) return forwardAwait(&scope, owner, try scope.invoke(source, "result", &.{}), 1);
        _ = try scope.invoke(try scope.get(owner, "outer"), "end", &.{c.pi_js_undefined()});
        return .{ .returned = c.pi_js_undefined() };
    }
    const event = try scope.get(value, "value");
    const generation = engine.native_allocation_generation;
    _ = scope.invoke(try scope.get(owner, "outer"), "push", &.{event}) catch |err| {
        if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
        const reason = try scope.own(flow.reason(engine, err));
        try scope.put(owner, "closeReason", reason);
        if (engine.captured_exception) |captured| {
            engine.captured_exception = null;
            engine.freeValue(captured);
        }
        const iterator = try scope.get(owner, "iterator");
        const closing_generation = engine.native_allocation_generation;
        const method = scope.get(iterator, "return") catch |closing_error| {
            if (engine.nativeAllocationError(closing_error, closing_generation) == error.OutOfMemory) return error.OutOfMemory;
            if (engine.captured_exception) |captured| {
                engine.captured_exception = null;
                engine.freeValue(captured);
            }
            return .{ .thrown = c.JS_DupValue(engine.context, reason) };
        };
        if (v.nullish(method)) return .{ .thrown = c.JS_DupValue(engine.context, reason) };
        const closing = scope.call(method, iterator, &.{}) catch |closing_error| {
            if (engine.nativeAllocationError(closing_error, closing_generation) == error.OutOfMemory) return error.OutOfMemory;
            if (engine.captured_exception) |captured| {
                engine.captured_exception = null;
                engine.freeValue(captured);
            }
            return .{ .thrown = c.JS_DupValue(engine.context, reason) };
        };
        return forwardAwait(&scope, owner, closing, 2);
    };
    return forwardNext(&scope, owner);
}
fn forward(engine: *v.em.Engine, outer: c.JSValue, source: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const function = try scope.own(try asynchronous.createResumable(engine, "forwardStream", 2, forwardBody, &.{ outer, source }));
    return v.js.call(engine, function, c.pi_js_undefined(), &.{ outer, source });
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
// The VM owns each invocation Promise and each actual Source await boundary.
fn setupBody(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, slot: *c.JSValue, completion: asynchronous.Completion, value: c.JSValue) !asynchronous.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const input = roots[0];
    if (completion == .start) {
        asynchronous.replaceState(engine, slot, c.JS_DupValue(engine.context, input));
        return .{ .awaited = c.JS_DupValue(engine.context, try scope.call(try scope.get(input, "load"), c.pi_js_undefined(), &.{})) };
    }
    if (completion == .rejected) return .{ .thrown = c.JS_DupValue(engine.context, value) };
    if (scope.truthy(try scope.get(input, "awaitingDiscard"))) return .{ .returned = c.pi_js_undefined() };
    const method = try scope.get(input, "method");
    const function = try scope.own(try v.js.getKey(engine, value, method));
    if (scope.truthy(try scope.get(input, "guard")) and !scope.truthy(function)) {
        const text = if (try v.eq(&scope, method, "cancelDeferred")) "API cannot cancel deferred responses" else "API does not support deferred responses";
        return .{ .thrown = try v.js.builtin(engine, "Error", &.{try scope.text(text)}) };
    }
    const invoked = if (scope.truthy(try scope.get(input, "guard"))) try scope.own(try v.js.getKey(engine, value, method)) else function;
    const result = try scope.call(invoked, value, &.{ try scope.get(input, "model"), try scope.get(input, "context"), try scope.get(input, "options") });
    if (scope.truthy(try scope.get(input, "discard"))) {
        try scope.put(input, "awaitingDiscard", c.JS_NewBool(engine.context, true));
        return .{ .awaited = c.JS_DupValue(engine.context, result) };
    }
    return .{ .returned = c.JS_DupValue(engine.context, result) };
}
fn operationInput(scope: *Scope, args: []const c.JSValue, roots: []const c.JSValue, guarded: bool, discard: bool) !c.JSValue {
    const input = try state(scope);
    try scope.put(input, "load", roots[0]);
    try scope.put(input, "method", roots[1]);
    try scope.put(input, "model", argument(args, 0));
    try scope.put(input, "context", argument(args, 1));
    try scope.put(input, "options", argument(args, 2));
    try scope.put(input, "guard", c.JS_NewBool(scope.engine.context, guarded));
    try scope.put(input, "discard", c.JS_NewBool(scope.engine.context, discard));
    return input;
}
fn operationBody(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, slot: *c.JSValue, completion: asynchronous.Completion, value: c.JSValue) !asynchronous.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const input = if (completion == .start) try operationInput(&scope, args, roots, scope.truthy(roots[2]), scope.truthy(roots[3])) else slot.*;
    return setupBody(engine, receiver, &.{}, &.{input}, slot, completion, value);
}
fn operation(engine: *v.em.Engine, args: []const c.JSValue, roots: []const c.JSValue, streaming: bool, guarded: bool, discard: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const input = try operationInput(&scope, args, roots, guarded, discard);
    const setup = try scope.own(try asynchronous.createResumableArrow(engine, "", 0, setupBody, &.{input}, c.pi_js_undefined()));
    return if (streaming) lazyStream(engine, argument(args, 0), setup) else v.js.call(engine, setup, c.pi_js_undefined(), &.{});
}
pub fn asyncOperation(engine: *v.em.Engine, load: c.JSValue, name: [*:0]const u8) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return asynchronous.createResumableArrow(engine, name, 3, operationBody, &.{ load, try scope.text(std.mem.span(name)), c.JS_NewBool(engine.context, false), c.JS_NewBool(engine.context, false) }, c.pi_js_undefined());
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
        const function = if (index == 3) try scope.own(try asynchronous.createResumableArrow(engine, method, 3, operationBody, &.{ roots[0], roots[1], c.JS_NewBool(engine.context, true), c.JS_NewBool(engine.context, true) }, c.pi_js_undefined())) else try scope.own(try functions.createArrow(engine, method, 3, Adapter.call, &roots));
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

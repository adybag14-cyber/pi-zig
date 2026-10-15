//! Source EventStream's ordinary live fields and native AsyncGenerator body.
//! This successor is source-only until its surface/queue/provider gates run.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const fifo = @import("native_event_stream_fifo.zig");
const gen = @import("native_async_generator.zig");
const c = em.c;
const Method = enum(c_int) { push, end, result, iterate };
const PromisePurpose = enum(c_int) { final, waiting };
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (args.len > index) args[index] else c.pi_js_undefined();
}
fn executePromise(engine: *em.Engine, receiver: c.JSValue, purpose: PromisePurpose, resolve: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (purpose) {
        .final => try scope.set(receiver, "resolveFinalResult", resolve),
        .waiting => _ = try scope.invoke(try scope.get(receiver, "waiting"), "enqueue", &.{resolve}),
    }
    return c.pi_js_undefined();
}
fn promise(engine: *em.Engine, receiver: c.JSValue, comptime purpose: PromisePurpose) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    // Source's `new Promise` is a live global lookup; Await itself subsequently
    // uses QuickJS's intrinsic PromiseResolve inside the actual generator.
    const promise_constructor = try scope.global("Promise");
    const Executor = struct {
        fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            return executePromise(host, roots[0], purpose, argument(args, 0));
        }
    };
    const callback = try scope.own(try @import("native_node_function.zig").createArrow(engine, "", 1, Executor.call, &.{receiver}));
    var args = [_]c.JSValue{callback};
    return engine.checked(c.JS_CallConstructor(engine.context, promise_constructor, args.len, &args));
}
pub fn initialize(engine: *em.Engine, receiver: c.JSValue, queue_constructor: c.JSValue, args: []const c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(receiver, "queue", try scope.own(try fifo.create(engine, queue_constructor)));
    try scope.put(receiver, "waiting", try scope.own(try fifo.create(engine, queue_constructor)));
    try scope.put(receiver, "done", c.pi_js_bool(engine.context, 0));
    // Type-only class fields are initialized before the constructor body.
    inline for (.{ "finalResultPromise", "resolveFinalResult", "isComplete", "extractResult" }) |name| try scope.put(receiver, name, c.pi_js_undefined());
    try scope.set(receiver, "isComplete", argument(args, 0));
    try scope.set(receiver, "extractResult", argument(args, 1));
    try scope.set(receiver, "finalResultPromise", try scope.own(try promise(engine, receiver, .final)));
}
fn iterationResult(scope: *Scope, value: c.JSValue, done: bool) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "value", value);
    try scope.put(result, "done", c.pi_js_bool(scope.engine.context, @intFromBool(done)));
    return result;
}
pub fn push(engine: *em.Engine, receiver: c.JSValue, value: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (scope.truthy(try scope.get(receiver, "done"))) return c.pi_js_undefined();
    if (scope.truthy(try scope.invoke(receiver, "isComplete", &.{value}))) {
        try scope.set(receiver, "done", c.pi_js_bool(engine.context, 1));
        // The resolver member is evaluated before the extractResult argument.
        const resolve = try scope.get(receiver, "resolveFinalResult");
        const final = try scope.invoke(receiver, "extractResult", &.{value});
        _ = try scope.call(resolve, receiver, &.{final});
    }
    const waiter = try scope.invoke(try scope.get(receiver, "waiting"), "dequeue", &.{});
    if (scope.truthy(waiter)) {
        _ = try scope.call(waiter, c.pi_js_undefined(), &.{try iterationResult(&scope, value, false)});
    } else {
        _ = try scope.invoke(try scope.get(receiver, "queue"), "enqueue", &.{value});
    }
    return c.pi_js_undefined();
}
fn waiting(engine: *em.Engine, receiver: c.JSValue) !bool {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return scope.positive(try scope.get(try scope.get(receiver, "waiting"), "length"));
}
pub fn end(engine: *em.Engine, receiver: c.JSValue, value: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.set(receiver, "done", c.pi_js_bool(engine.context, 1));
    if (!c.JS_IsUndefined(value)) _ = try scope.invoke(receiver, "resolveFinalResult", &.{value});
    while (try waiting(engine, receiver)) {
        var row: Scope = .{ .engine = engine };
        defer row.deinit();
        const waiter = try row.invoke(try row.get(receiver, "waiting"), "dequeue", &.{});
        _ = try row.call(waiter, c.pi_js_undefined(), &.{try iterationResult(&row, c.pi_js_undefined(), true)});
    }
    return c.pi_js_undefined();
}
/// Internal host-fatal bridge: use the live Source resolvers and real Promise
/// rejection assimilation, without an additional strong private reject root.
pub fn reject(engine: *em.Engine, receiver: c.JSValue, failure: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.set(receiver, "done", c.pi_js_bool(engine.context, 1));
    const rejected = try scope.own(try engine.checked(c.JS_NewSettledPromise(engine.context, true, failure)));
    _ = try scope.invoke(receiver, "resolveFinalResult", &.{rejected});
    while (try waiting(engine, receiver)) {
        var row: Scope = .{ .engine = engine };
        defer row.deinit();
        const waiter = try row.invoke(try row.get(receiver, "waiting"), "dequeue", &.{});
        _ = try row.call(waiter, c.pi_js_undefined(), &.{rejected});
    }
}
fn advance(engine: *em.Engine, owner: c.JSValue, completion: gen.Completion, input: c.JSValue) !gen.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "receiver");
    switch (completion) {
        .returned => return .{ .complete = c.JS_DupValue(engine.context, input) },
        .thrown, .rejected => return .{ .thrown = c.JS_DupValue(engine.context, input) },
        .fulfilled => {
            // The Source const result remains live across `yield result.value`.
            // Preserve that local, including a caller-supplied result object.
            try scope.set(owner, "result", input);
            if (scope.truthy(try scope.get(input, "done"))) return .{ .complete = c.pi_js_undefined() };
            return .{ .yielded = c.JS_DupValue(engine.context, try scope.get(input, "value")) };
        },
        .start, .next => {},
    }
    try scope.set(owner, "result", c.pi_js_undefined());
    if (try scope.positive(try scope.get(try scope.get(receiver, "queue"), "length"))) {
        // Reload queue exactly as the Source member expression does.
        return .{ .yielded = c.JS_DupValue(engine.context, try scope.invoke(try scope.get(receiver, "queue"), "dequeue", &.{})) };
    }
    if (scope.truthy(try scope.get(receiver, "done"))) return .{ .complete = c.pi_js_undefined() };
    return .{ .awaited = try promise(engine, receiver, .waiting) };
}
pub fn iterator(engine: *em.Engine, receiver: c.JSValue, prototype: c.JSValue) !c.JSValue {
    // Calling an async-generator method captures any receiver without entering
    // the body. Property access and receiver failures occur on first next.
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.object();
    try scope.put(owner, "receiver", receiver);
    try scope.put(owner, "result", c.pi_js_undefined());
    const selected = if (c.JS_IsObject(prototype)) prototype else try scope.own(try gen.prototype(engine));
    return gen.create(engine, owner, advance, selected);
}
fn function(engine: *em.Engine, comptime operation: Method, roots: []const c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn call(host: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
            return dispatch(host, receiver, operation, argument(args, 0), values);
        }
    };
    return @import("native_node_function.zig").createMethod(engine, if (operation == .iterate) "[Symbol.asyncIterator]" else @tagName(operation), if (operation == .push or operation == .end) 1 else 0, Adapter.call, roots);
}
fn dispatch(engine: *em.Engine, receiver: c.JSValue, operation: Method, value: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return switch (operation) {
        .push => push(engine, receiver, value),
        .end => end(engine, receiver, value),
        .result => js.get(engine, receiver, "finalResultPromise"),
        .iterate => actual: {
            var scope: Scope = .{ .engine = engine };
            defer scope.deinit();
            // AsyncGeneratorFunction creation reads its live own prototype on
            // each invocation, even after a caller replaces that property.
            break :actual iterator(engine, receiver, try scope.get(try scope.get(roots[0], "function"), "prototype"));
        },
    };
}
fn construct(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const instance = try @import("native_class.zig").object(engine, target);
    errdefer engine.freeValue(instance);
    try initialize(engine, instance, roots[0], args);
    return instance;
}
pub fn constructor(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.object();
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    inline for (.{ Method.push, Method.end }) |operation| {
        const method_value = try function(engine, operation, &.{});
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, @tagName(operation), method_value, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    const generator_parent = try scope.own(try gen.prototype(engine));
    const generator_prototype = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, generator_parent)));
    const function_owner = try scope.object();
    const iterate = try scope.own(try function(engine, .iterate, &.{function_owner}));
    if (c.JS_SetPrototype(engine.context, iterate, try scope.own(try gen.functionPrototype(engine))) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, iterate, "prototype", c.JS_DupValue(engine.context, generator_prototype), c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    try scope.put(function_owner, "function", iterate);
    const symbol = try scope.own(try engine.checked(c.JS_GetAsyncIteratorSymbol(engine.context)));
    const atom = c.JS_ValueToAtom(engine.context, symbol);
    if (atom == c.JS_ATOM_NULL) return js.capture(engine);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyValue(engine.context, prototype, atom, c.JS_DupValue(engine.context, iterate), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    const result = try function(engine, .result, &.{});
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "result", result, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    return @import("native_class.zig").constructor(engine, "EventStream", 2, prototype, construct, &.{try scope.own(try fifo.constructor(engine))});
}

//! Source readMistralEvents on the qualified VM AsyncGenerator Await/yield path.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const gen = @import("native_async_generator.zig");
const parser = @import("native_ai_mistral_sse.zig");
const Stage = enum(c_int) { initial, reading, yielded, closing, finished };
const Final = enum(c_int) { normal, returned, thrown };
pub fn create(engine: *v.em.Engine, body: c.JSValue, parser_owner: c.JSValue, signal: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.object();
    try scope.put(owner, "body", body);
    try scope.put(owner, "reader", c.pi_js_undefined());
    try scope.put(owner, "onAbort", c.pi_js_undefined());
    try scope.put(owner, "parser", parser_owner);
    try scope.put(owner, "signal", signal);
    try scope.put(owner, "stage", c.JS_NewInt32(engine.context, @intFromEnum(Stage.initial)));
    try scope.put(owner, "final", c.JS_NewInt32(engine.context, @intFromEnum(Final.normal)));
    try scope.put(owner, "value", c.pi_js_undefined());
    try scope.put(owner, "entered", c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "closeGeneration", c.JS_NewInt64(engine.context, @intCast(engine.native_allocation_generation)));
    const parent = try scope.own(try gen.prototype(engine));
    const prototype = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, parent)));
    return gen.create(engine, owner, advance, prototype);
}
fn stage(scope: *Scope, owner: c.JSValue) !Stage {
    var value: i32 = 0;
    if (c.JS_ToInt32(scope.engine.context, &value, try scope.get(owner, "stage")) < 0) return v.js.capture(scope.engine);
    return @enumFromInt(value);
}
fn setStage(scope: *Scope, owner: c.JSValue, value: Stage) !void {
    try scope.put(owner, "stage", c.JS_NewInt32(scope.engine.context, @intFromEnum(value)));
}
fn checkAbort(scope: *Scope, owner: c.JSValue) !void {
    const signal = try scope.get(owner, "signal");
    if (scope.truthy(try v.optional(scope, signal, "aborted"))) {
        _ = try scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, try scope.get(signal, "reason"))));
        unreachable;
    }
}
fn begin(scope: *Scope, owner: c.JSValue) !void {
    // These operations precede Source's try/finally. If a getter, decoder or
    // listener setup throws, the generator must not enter that finally.
    try scope.put(owner, "reader", try scope.invoke(try scope.get(owner, "body"), "getReader", &.{}));
    try parser.start(scope, try scope.get(owner, "parser"));
    const OnAbort = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = engine };
            defer row.deinit();
            const cancelled = try row.invoke(try row.get(roots[0], "reader"), "cancel", &.{});
            const Ignore = struct {
                fn call(_: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
                    return c.pi_js_undefined();
                }
            };
            _ = try row.invoke(cancelled, "catch", &.{try row.own(try @import("native_node_function.zig").createArrow(engine, "", 0, Ignore.call, &.{}))});
            return c.pi_js_undefined();
        }
    };
    const listener = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "onAbort", 0, OnAbort.call, &.{owner}));
    try scope.put(owner, "onAbort", listener);
    const signal = try scope.get(owner, "signal");
    if (!v.nullish(signal)) {
        const options = try scope.object();
        try scope.put(options, "once", c.pi_js_bool(scope.engine.context, 1));
        _ = try scope.invoke(signal, "addEventListener", &.{ try scope.text("abort"), listener, options });
    }
    try scope.put(owner, "entered", c.pi_js_bool(scope.engine.context, 1));
}
fn release(scope: *Scope, owner: c.JSValue) !void {
    const generation = scope.engine.native_allocation_generation;
    _ = scope.invoke(try scope.get(owner, "reader"), "releaseLock", &.{}) catch |err| {
        try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
        return;
    };
}
fn retire(scope: *Scope, owner: c.JSValue, mode: Final, value: c.JSValue) !gen.Action {
    try scope.put(owner, "final", c.JS_NewInt32(scope.engine.context, @intFromEnum(mode)));
    try scope.put(owner, "value", value);
    if (!scope.truthy(try scope.get(owner, "entered"))) return finish(scope, owner);
    try setStage(scope, owner, .closing);
    try scope.put(owner, "closeGeneration", c.JS_NewInt64(scope.engine.context, @intCast(scope.engine.native_allocation_generation)));
    const signal = try scope.get(owner, "signal");
    if (!v.nullish(signal)) _ = try scope.invoke(signal, "removeEventListener", &.{ try scope.text("abort"), try scope.get(owner, "onAbort") });
    const generation = scope.engine.native_allocation_generation;
    const closed = scope.invoke(try scope.get(owner, "reader"), "cancel", &.{}) catch |err| {
        try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
        try release(scope, owner);
        return finish(scope, owner);
    };
    return .{ .awaited = c.JS_DupValue(scope.engine.context, closed) };
}
fn finish(scope: *Scope, owner: c.JSValue) !gen.Action {
    try setStage(scope, owner, .finished);
    var mode: i32 = 0;
    if (c.JS_ToInt32(scope.engine.context, &mode, try scope.get(owner, "final")) < 0) return v.js.capture(scope.engine);
    const value = c.JS_DupValue(scope.engine.context, try scope.get(owner, "value"));
    return if (@as(Final, @enumFromInt(mode)) == .thrown) .{ .thrown = value } else .{ .complete = value };
}
fn advance(engine: *v.em.Engine, owner: c.JSValue, completion: gen.Completion, input: c.JSValue) !gen.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return run(&scope, owner, completion, input) catch |err| {
        const reason = try scope.own(@import("native_agent_async.zig").reason(engine, err));
        if (try stage(&scope, owner) == .closing) return .{ .thrown = c.JS_DupValue(engine.context, reason) };
        return retire(&scope, owner, .thrown, reason);
    };
}
fn run(scope: *Scope, owner: c.JSValue, completion: gen.Completion, input: c.JSValue) !gen.Action {
    const current = try stage(scope, owner);
    if (scope.engine.native_io) |io| @import("std").debug.print("DIAG_MISTRAL_RESUME t={d} stage={s} completion={s} jobs={d} controls={d}\n", .{ @import("std").Io.Clock.awake.now(io).toNanoseconds(), @tagName(current), @tagName(completion), if (scope.engine.progress_probe) |probe| probe.job_attempts else 0, if (scope.engine.progress_probe) |probe| probe.control_pumps else 0 });
    if (current == .closing and (completion == .fulfilled or completion == .rejected)) {
        var generation: i64 = 0;
        if (c.JS_ToInt64(scope.engine.context, &generation, try scope.get(owner, "closeGeneration")) < 0) return v.js.capture(scope.engine);
        try release(scope, owner);
        if (completion == .rejected and (c.JS_IsUncatchableError(input) or scope.engine.native_allocation_generation != @as(u64, @intCast(generation)))) return .{ .thrown = c.JS_DupValue(scope.engine.context, input) };
        return finish(scope, owner);
    }
    if (completion == .returned) return retire(scope, owner, .returned, input);
    if (completion == .thrown or completion == .rejected) return retire(scope, owner, .thrown, input);
    const state = try scope.get(owner, "parser");
    if (current == .initial) {
        try begin(scope, owner);
    } else if (current == .reading and completion == .fulfilled) {
        const done = scope.truthy(try scope.get(input, "done"));
        const bytes = try scope.get(input, "value");
        try checkAbort(scope, owner);
        if (done) {
            try parser.feed(scope, state, c.pi_js_undefined(), true);
        } else {
            try parser.feed(scope, state, bytes, false);
        }
    }
    switch (try parser.pop(scope, state)) {
        .eof, .done => return retire(scope, owner, .normal, c.pi_js_undefined()),
        .data => |value| {
            const event = try scope.object();
            try scope.put(event, "data", value);
            try setStage(scope, owner, .yielded);
            return .{ .yielded = c.JS_DupValue(scope.engine.context, event) };
        },
        .need_bytes => {
            try checkAbort(scope, owner);
            try setStage(scope, owner, .reading);
            return .{ .awaited = c.JS_DupValue(scope.engine.context, try scope.invoke(try scope.get(owner, "reader"), "read", &.{})) };
        },
    }
}

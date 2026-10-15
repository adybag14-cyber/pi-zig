//! Actual bundled ReadableStreamFrom underlying byte source. Stream algorithms
//! remain in Env; dynamic iterator/Buffer calls are deliberately observable.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const body = @import("native_web_body.zig");
const c = em.c;
const Kind = enum(c_int) { start, pull, cancel, fulfilled };
fn closeJob(context: ?*c.JSContext, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    close(&scope, captures[0]) catch |err| return @import("native_sdk.zig").fail(engine, err);
    return c.pi_js_undefined();
}
fn close(scope: *Scope, controller: c.JSValue) !void {
    _ = try scope.invoke(controller, "close", &.{});
    const request = try scope.get(controller, "byobRequest");
    if (!c.JS_IsNull(request) and !c.JS_IsUndefined(request)) _ = try scope.invoke(request, "respond", &.{c.JS_NewInt32(scope.engine.context, 0)});
}
fn function(scope: *Scope, state: c.JSValue, kind: Kind, name: [*:0]const u8, length: c_int) !c.JSValue {
    var captures = [_]c.JSValue{state};
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, dispatch, name, length, @intFromEnum(kind), 1, &captures)));
}
fn operation(scope: *Scope, receiver: c.JSValue, state: c.JSValue, args: []const c.JSValue, kind: Kind) anyerror!c.JSValue {
    const engine = scope.engine;
    switch (kind) {
        .start => {
            const iterable = try scope.get(state, "iterable");
            const symbol = try scope.own(try engine.checked(c.JS_GetAsyncIteratorSymbol(engine.context)));
            const method = try scope.own(try js.getKey(engine, iterable, symbol));
            try scope.set(state, "iterator", try scope.call(method, iterable, &.{}));
            return c.pi_js_undefined();
        },
        .cancel => return scope.invoke(try scope.get(state, "iterator"), "return", &.{}),
        .pull => {
            const controller = if (args.len > 0) args[0] else c.pi_js_undefined();
            const call_state = try scope.object();
            try scope.set(call_state, "state", state);
            try scope.set(call_state, "source", receiver);
            try scope.set(call_state, "controller", controller);
            const next = try scope.invoke(try scope.get(state, "iterator"), "next", &.{});
            return scope.invoke(next, "then", &.{try function(scope, call_state, .fulfilled, "", 1)});
        },
        .fulfilled => {
            const row = if (args.len > 0) args[0] else c.pi_js_undefined();
            const done = try scope.get(row, "done");
            // Destructuring reads value even on the done path.
            const value = try scope.get(row, "value");
            const controller = try scope.get(state, "controller");
            if (scope.truthy(done)) {
                var captures = [_]c.JSValue{controller};
                if (c.JS_EnqueueJob(engine.context, closeJob, 1, &captures) < 0) return js.capture(engine);
                return c.pi_js_undefined();
            }
            const binding = try scope.get(state, "state");
            const buffer = try scope.get(binding, "Buffer");
            const bytes = if (scope.truthy(try scope.invoke(buffer, "isBuffer", &.{value}))) value else try scope.invoke(buffer, "from", &.{value});
            if (scope.truthy(try scope.get(bytes, "byteLength"))) return scope.invoke(controller, "enqueue", &.{try scope.own(try js.builtin(engine, "Uint8Array", &.{bytes}))});
            return scope.invoke(try scope.get(state, "source"), "pull", &.{controller});
        },
    }
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const value = operation(&scope, receiver, captures[0], if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(raw)) catch |err| return @import("native_sdk.zig").fail(engine, err);
    return c.JS_DupValue(context, value);
}
/// Borrowed iterable; returned stream is owned and genuinely Env branded.
pub fn fromIterable(engine: *em.Engine, iterable: c.JSValue) !c.JSValue {
    try body.require(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.object();
    try scope.set(state, "iterable", iterable);
    try @import("node_buffer.zig").install(engine);
    try scope.set(state, "Buffer", try scope.global("Buffer"));
    const source = try scope.object();
    inline for (.{ .{ Kind.start, "start", 0 }, .{ Kind.pull, "pull", 1 }, .{ Kind.cancel, "cancel", 0 } }) |spec| try scope.set(source, spec[1], try function(&scope, state, spec[0], spec[1], spec[2]));
    try scope.set(source, "type", try scope.text("bytes"));
    var args = [_]c.JSValue{source};
    return engine.checked(c.JS_CallConstructor(engine.context, try body.streamConstructor(&scope), 1, &args));
}

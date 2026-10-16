//! Readable.from and fromWeb retain their original synchronous/await boundaries.
//! Async input uses the reviewed genuine native AsyncFunction continuation;
//! WHATWG input retains its real reader and intrinsic Promise reactions.
const core = @import("native_node_stream.zig");
const em = core.em; const c = core.c; const js = core.js; const Scope = core.Scope;
const fnc = @import("native_node_function.zig");
const af = @import("native_async_function.zig");
const buffer = @import("node_buffer.zig");
const web = @import("native_readable_stream.zig");
const Op = enum(c_int) { scalar_read, from_read, from_destroy, close_ok, close_error, web_read, web_chunk, web_error, web_closed, web_closed_error, web_destroy, web_destroy_done, throw_tick };
fn private(scope: *Scope) !c.JSValue { return scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, c.pi_js_null()))); }
fn flag(scope: *Scope, data: c.JSValue, key: [*:0]const u8) !bool { return scope.truthy(try scope.get(data, key)); }
fn setFlag(scope: *Scope, data: c.JSValue, key: [*:0]const u8, value: bool) !void { try scope.put(data, key, c.pi_js_bool(scope.engine.context, @intFromBool(value))); }
fn function(scope: *Scope, data: c.JSValue, name: [*:0]const u8, length: c_int, op: Op, method: bool) !c.JSValue {
    const roots = [_]c.JSValue{ data, c.JS_NewInt32(scope.engine.context, @intFromEnum(op)) };
    return scope.own(if (method) try fnc.createMethod(scope.engine, name, length, dispatch, &roots) else if (op == .from_read or op == .from_destroy or op == .web_destroy_done) try fnc.create(scope.engine, name, length, dispatch, &roots) else try fnc.createArrow(scope.engine, name, length, dispatch, &roots));
}
fn then(scope: *Scope, promise: c.JSValue, yes: c.JSValue, no: c.JSValue) !void { _ = try scope.call(try scope.get(try core.owner(scope.engine), "promiseThen"), promise, &.{ yes, no }); }
fn throwNull(scope: *Scope) !void {
    const reason = try scope.own(try core.errorValue(scope, "TypeError", "ERR_STREAM_NULL_VALUES", "May not write null values to stream"));
    _ = try scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, reason)));
}
fn push(scope: *Scope, data: c.JSValue, value: c.JSValue) !bool { return scope.truthy(try scope.invoke(try scope.get(data, "readable"), "push", &.{value})); }
fn destroy(scope: *Scope, data: c.JSValue, reason: c.JSValue) !void { _ = try scope.invoke(try scope.get(data, "readable"), "destroy", &.{reason}); }
fn thenable(scope: *Scope, value: c.JSValue) !bool { return scope.truthy(value) and c.JS_IsFunction(scope.engine.context, try scope.get(value, "then")); }
fn checkpoint(engine: *em.Engine, count: *usize) !void {
    count.* +|= 1;
    if (engine.cancelled.load(.acquire) or (count.* % 256 == 0 and blk: { engine.interrupts +|= 1; break :blk engine.interrupts > engine.options.interrupt_budget; })) {
        _ = try engine.checked(c.JS_ThrowInternalError(engine.context, "interrupted"));
    }
}
fn syncRead(scope: *Scope, data: c.JSValue) !void {
    var count: usize = 0;
    while (true) {
        var iteration_roots: Scope = .{ .engine = scope.engine }; defer iteration_roots.deinit(); const step_scope = &iteration_roots;
        try checkpoint(step_scope.engine, &count);
        const step = try step_scope.invoke(try step_scope.get(data, "iterator"), "next", &.{});
        // The source destructures value before done (including observable getters).
        const value = try step_scope.get(step, "value"); const done = try step_scope.get(step, "done");
        if (step_scope.truthy(done)) { _ = try push(step_scope, data, c.pi_js_null()); return; }
        if (try thenable(step_scope, value)) {
            try setFlag(step_scope, data, "asyncValues", true);
            _ = try step_scope.call(try step_scope.get(data, "nextAsync"), c.pi_js_undefined(), &.{value}); return;
        }
        if (c.JS_IsNull(value)) { try setFlag(step_scope, data, "reading", false); try throwNull(step_scope); }
        if (!try push(step_scope, data, value)) { try setFlag(step_scope, data, "reading", false); return; }
    }
}
fn from(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const iterable = core.arg(args, 0); const data = try private(&scope);
    const options = try scope.object(); try scope.put(options, "objectMode", c.pi_js_bool(engine.context, 1));
    if (c.JS_IsString(iterable) or try buffer.isBuffer(engine, iterable)) {
        try js.spreadInto(engine, options, core.arg(args, 1)); try scope.put(data, "value", iterable);
        try scope.put(options, "read", try function(&scope, data, "read", 0, .scalar_read, true));
        return core.createReadable(engine, options);
    }
    const module = try core.owner(engine); var iterator = c.pi_js_undefined(); var is_async = false;
    const async_method = if (core.nullish(iterable)) c.pi_js_undefined() else try scope.own(try js.getKey(engine, iterable, try scope.get(module, "asyncIteratorSymbol")));
    if (scope.truthy(async_method)) {
        is_async = true;
        // Node checks and invokes separate live property reads.
        iterator = try scope.call(try scope.own(try js.getKey(engine, iterable, try scope.get(module, "asyncIteratorSymbol"))), iterable, &.{});
    } else {
        const sync_method = if (core.nullish(iterable)) c.pi_js_undefined() else try scope.own(try js.getKey(engine, iterable, try scope.get(module, "iteratorSymbol")));
        if (!scope.truthy(sync_method)) return @import("node_events.zig").codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", "The \"iterable\" argument must be an instance of Iterable");
        iterator = try scope.call(try scope.own(try js.getKey(engine, iterable, try scope.get(module, "iteratorSymbol"))), iterable, &.{});
    }
    try scope.put(data, "iterator", iterator); try setFlag(&scope, data, "isAsync", is_async); try setFlag(&scope, data, "asyncValues", false); try setFlag(&scope, data, "reading", false);
    try scope.put(options, "highWaterMark", c.JS_NewInt32(engine.context, 1)); try js.spreadInto(engine, options, core.arg(args, 1));
    const readable = try scope.own(try core.createReadable(engine, options)); try scope.put(data, "readable", readable);
    try scope.put(data, "nextAsync", try scope.own(try af.createResumable(engine, if (is_async) "nextAsync" else "nextSyncWithAsyncValues", 0, readBody, &.{data})));
    try scope.put(data, "close", try scope.own(try af.createResumable(engine, "close", 1, closeBody, &.{data})));
    try scope.set(readable, "_read", try function(&scope, data, "", 0, .from_read, false));
    try scope.set(readable, "_destroy", try function(&scope, data, "", 2, .from_destroy, false));
    return c.JS_DupValue(engine.context, readable);
}
// Invocation state is private GC-visible data, never a guest iterator facade.
fn readBody(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, slot: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    return readStep(&scope, args, roots[0], slot, completion, input) catch |err| {
        if (err != error.JavaScriptException) return err;
        const reason = try scope.own(c.JS_DupValue(engine.context, engine.captured_exception.?)); try destroy(&scope, roots[0], reason);
        return .{ .returned = c.pi_js_undefined() };
    };
}
fn readStep(scope: *Scope, args: []const c.JSValue, data: c.JSValue, slot: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var phase: i32 = 0;
    if (completion == .start) {
        const state = try private(scope); af.replaceState(scope.engine, slot, c.JS_DupValue(scope.engine.context, state));
        if (!try flag(scope, data, "isAsync") and args.len > 0) { try scope.put(state, "phase", c.JS_NewInt32(scope.engine.context, 2)); return .{ .awaited = c.JS_DupValue(scope.engine.context, args[0]) }; }
    } else {
        if (completion == .rejected) { _ = try scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, input))); unreachable; }
        if (c.JS_ToInt32(scope.engine.context, &phase, try scope.get(slot.*, "phase")) < 0) return js.capture(scope.engine);
    }
    var resumed = completion != .start; var count: usize = 0;
    while (true) {
        var iteration_roots: Scope = .{ .engine = scope.engine }; defer iteration_roots.deinit(); const step_scope = &iteration_roots;
        try checkpoint(step_scope.engine, &count);
        var value = c.pi_js_undefined();
        if (resumed and phase == 2) { value = input; resumed = false; }
        else {
            var step = c.pi_js_undefined();
            if (resumed) { step = input; resumed = false; }
            else {
                step = try step_scope.invoke(try step_scope.get(data, "iterator"), "next", &.{});
                if (try flag(step_scope, data, "isAsync")) { try step_scope.put(slot.*, "phase", c.JS_NewInt32(step_scope.engine.context, 1)); return .{ .awaited = c.JS_DupValue(step_scope.engine.context, step) }; }
            }
            value = try step_scope.get(step, "value"); const done = try step_scope.get(step, "done");
            if (step_scope.truthy(done)) { _ = try push(step_scope, data, c.pi_js_null()); return .{ .returned = c.pi_js_undefined() }; }
            if (!try flag(step_scope, data, "isAsync") and try thenable(step_scope, value)) { try step_scope.put(slot.*, "phase", c.JS_NewInt32(step_scope.engine.context, 2)); return .{ .awaited = c.JS_DupValue(step_scope.engine.context, value) }; }
        }
        if (c.JS_IsNull(value)) { try setFlag(step_scope, data, "reading", false); try throwNull(step_scope); }
        if (!try push(step_scope, data, value)) { try setFlag(step_scope, data, "reading", false); return .{ .returned = c.pi_js_undefined() }; }
    }
}
fn closeBody(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, slot: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const iterator = try scope.get(roots[0], "iterator"); var phase: i32 = 0;
    if (completion == .rejected) return .{ .thrown = c.JS_DupValue(engine.context, input) };
    if (completion == .start) {
        const state = try private(&scope); af.replaceState(engine, slot, c.JS_DupValue(engine.context, state));
        const had_error = !core.nullish(core.arg(args, 0)); const has_throw = c.JS_IsFunction(engine.context, try scope.get(iterator, "throw"));
        if (had_error and has_throw) { try scope.put(state, "phase", c.JS_NewInt32(engine.context, 1)); return .{ .awaited = c.JS_DupValue(engine.context, try scope.invoke(iterator, "throw", &.{core.arg(args, 0)})) }; }
    } else if (c.JS_ToInt32(engine.context, &phase, try scope.get(slot.*, "phase")) < 0) return js.capture(engine);
    if (phase == 1) {
        const value = try scope.get(input, "value"); try scope.put(slot.*, "done", try scope.get(input, "done")); try scope.put(slot.*, "phase", c.JS_NewInt32(engine.context, 2)); return .{ .awaited = c.JS_DupValue(engine.context, value) };
    }
    if (phase == 2 and try flag(&scope, slot.*, "done")) return .{ .returned = c.pi_js_undefined() };
    if (phase == 3) { try scope.put(slot.*, "phase", c.JS_NewInt32(engine.context, 4)); return .{ .awaited = c.JS_DupValue(engine.context, try scope.get(input, "value")) }; }
    if (phase == 4) return .{ .returned = c.pi_js_undefined() };
    if (c.JS_IsFunction(engine.context, try scope.get(iterator, "return"))) { try scope.put(slot.*, "phase", c.JS_NewInt32(engine.context, 3)); return .{ .awaited = c.JS_DupValue(engine.context, try scope.invoke(iterator, "return", &.{})) }; }
    return .{ .returned = c.pi_js_undefined() };
}
fn fromWeb(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const supplied = core.arg(args, 0); const opts = if (c.JS_IsUndefined(core.arg(args, 1))) try scope.object() else core.arg(args, 1);
    if (!try web.isReadableStream(engine, supplied)) return @import("node_events.zig").codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", "The \"readableStream\" argument must be an instance of ReadableStream");
    if (!c.JS_IsObject(opts) or c.JS_IsArray(opts) or c.JS_IsFunction(engine.context, opts)) return @import("node_events.zig").codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", "The \"options\" argument must be of type object");
    const hwm = try scope.get(opts, "highWaterMark"); const enc = try scope.get(opts, "encoding"); var object_mode = try scope.get(opts, "objectMode"); const signal = try scope.get(opts, "signal");
    if (c.JS_IsUndefined(object_mode)) object_mode = c.pi_js_bool(engine.context, 0);
    if (!c.JS_IsUndefined(enc)) {
        const buffer_ctor = try scope.get(engine.native_module_values.get("node:buffer").?, "Buffer");
        if (!scope.truthy(try scope.invoke(buffer_ctor, "isEncoding", &.{enc}))) return @import("node_events.zig").codedError(engine, "TypeError", "ERR_INVALID_ARG_VALUE", "The argument 'options.encoding' is invalid");
    }
    if (!c.JS_IsBool(object_mode)) return @import("node_events.zig").codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", "The \"options.objectMode\" property must be of type boolean");
    const data = try private(&scope); try scope.put(data, "reader", try scope.invoke(supplied, "getReader", &.{})); try setFlag(&scope, data, "closed", false);
    const options = try scope.object(); inline for (.{ "highWaterMark", "encoding", "objectMode", "signal" }, .{ hwm, enc, object_mode, signal }) |key, value| try scope.put(options, key, value);
    try scope.put(options, "read", try function(&scope, data, "read", 0, .web_read, true)); try scope.put(options, "destroy", try function(&scope, data, "destroy", 2, .web_destroy, true));
    const readable = try scope.own(try core.createReadable(engine, options)); try scope.put(data, "readable", readable);
    try then(&scope, try scope.get(try scope.get(data, "reader"), "closed"), try function(&scope, data, "", 0, .web_closed, false), try function(&scope, data, "", 1, .web_closed_error, false));
    return c.JS_DupValue(engine.context, readable);
}
fn dispatch(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const data = roots[0]; var raw: i32 = 0; if (c.JS_ToInt32(engine.context, &raw, roots[1]) < 0) return js.capture(engine); const op: Op = @enumFromInt(raw);
    switch (op) {
        .scalar_read => { _ = try scope.invoke(receiver, "push", &.{try scope.get(data, "value")}); _ = try scope.invoke(receiver, "push", &.{c.pi_js_null()}); },
        .from_read => if (!try flag(&scope, data, "reading")) {
            try setFlag(&scope, data, "reading", true);
            if (try flag(&scope, data, "isAsync") or try flag(&scope, data, "asyncValues")) _ = try scope.call(try scope.get(data, "nextAsync"), c.pi_js_undefined(), &.{}) else syncRead(&scope, data) catch |err| { if (err != error.JavaScriptException) return err; const reason = try scope.own(c.JS_DupValue(engine.context, engine.captured_exception.?)); try destroy(&scope, data, reason); };
        },
        .from_destroy => {
            const record = try private(&scope); try scope.put(record, "error", core.arg(args, 0)); try scope.put(record, "callback", core.arg(args, 1));
            const pending = try scope.call(try scope.get(data, "close"), c.pi_js_undefined(), &.{core.arg(args, 0)});
            try then(&scope, pending, try function(&scope, record, "", 0, .close_ok, false), try function(&scope, record, "", 1, .close_error, false));
        },
        .close_ok, .close_error => try core.tick(&scope, try scope.get(data, "callback"), &.{if (op == .close_error and scope.truthy(core.arg(args, 0))) core.arg(args, 0) else try scope.get(data, "error")}),
        .web_read => { const pending = try scope.invoke(try scope.get(data, "reader"), "read", &.{}); try then(&scope, pending, try function(&scope, data, "", 1, .web_chunk, false), try function(&scope, data, "", 1, .web_error, false)); },
        .web_chunk => { const chunk = core.arg(args, 0); _ = try push(&scope, data, if (scope.truthy(try scope.get(chunk, "done"))) c.pi_js_null() else try scope.get(chunk, "value")); },
        .web_error => try destroy(&scope, data, core.arg(args, 0)),
        .web_closed, .web_closed_error => { try setFlag(&scope, data, "closed", true); if (op == .web_closed_error) try destroy(&scope, data, core.arg(args, 0)); },
        .web_destroy => {
            const record = try private(&scope); try scope.put(record, "error", core.arg(args, 0)); try scope.put(record, "callback", core.arg(args, 1)); const done = try function(&scope, record, "done", 0, .web_destroy_done, false);
            if (!try flag(&scope, data, "closed")) try then(&scope, try scope.invoke(try scope.get(data, "reader"), "cancel", &.{core.arg(args, 0)}), done, done) else _ = try scope.call(done, c.pi_js_undefined(), &.{});
        },
        .web_destroy_done => { _ = scope.call(try scope.get(data, "callback"), c.pi_js_undefined(), &.{try scope.get(data, "error")}) catch |err| { if (err != error.JavaScriptException) return err; const record = try private(&scope); try scope.put(record, "error", engine.captured_exception.?); try core.tick(&scope, try function(&scope, record, "", 0, .throw_tick, false), &.{}); return c.pi_js_undefined(); }; },
        .throw_tick => { _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, try scope.get(data, "error")))); },
    }
    return c.pi_js_undefined();
}
pub fn install(engine: *em.Engine, module: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    const symbol = try scope.global("Symbol"); try scope.put(module, "iteratorSymbol", try scope.get(symbol, "iterator")); try scope.put(module, "asyncIteratorSymbol", try scope.get(symbol, "asyncIterator"));
    try scope.put(module, "promiseThen", try scope.get(try scope.get(try scope.global("Promise"), "prototype"), "then"));
    const readable = try scope.get(module, "Readable"); try scope.put(readable, "from", try scope.own(try fnc.create(engine, "", 2, from, &.{}))); try scope.put(readable, "fromWeb", try scope.own(try fnc.create(engine, "", 2, fromWeb, &.{})));
}

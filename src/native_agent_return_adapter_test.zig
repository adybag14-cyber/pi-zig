//! Prepared controls for genuine production Agent AF entry points. Unrun.
const std = @import("std");
const em = @import("extensions/engine.zig");
const returned = @import("extensions/native_async_return.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
const functions = @import("extensions/native_node_function.zig");

fn echo(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.JS_DupValue(engine.context, if (args.len > 0) args[0] else c.pi_js_undefined());
}
fn reflect(engine: *em.Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const value = try s.object();
    try s.put(value, "receiver", receiver);
    try s.put(value, "capture", roots[0]);
    return c.JS_DupValue(engine.context, value);
}
fn thrower(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, args[0])));
}
fn global(s: *Scope) !c.JSValue { return s.own(c.JS_GetGlobalObject(s.engine.context)); }
fn run(engine: *em.Engine, source: []const u8, name: [:0]const u8) !void {
    const result = try engine.evalModule(source, name);
    engine.freeValue(result);
}

test "native Agent return adapter actual Promise adoption strict receiver captures and nonconstructor" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const g = try global(&s); const capture = try s.object();
    const echo_function = try s.own(try returned.create(engine, "returnEcho", 1, echo, &.{}));
    try std.testing.expect(c.JS_IsAsyncFunction(echo_function));
    try s.put(g, "returnEcho", echo_function);
    try s.put(g, "returnReflect", try s.own(try returned.create(engine, "returnReflect", 0, reflect, &.{capture})));
    try s.put(g, "returnArrow", try s.own(try returned.createArrow(engine, "returnArrow", 0, reflect, &.{capture}, capture)));
    try s.put(g, "capture", capture);
    try run(engine,
        \\if(returnEcho.name!=='returnEcho'||returnEcho.length!==1||Object.hasOwn(returnEcho,'prototype'))throw Error('metadata');
        \\let constructed=false;try{new returnEcho()}catch(e){constructed=e instanceof TypeError}if(!constructed)throw Error('constructor');
        \\const receiver={};const reflected=await returnReflect.call(receiver);if(reflected.receiver!==receiver||reflected.capture!==capture)throw Error('receiver/capture');
        \\if((await returnArrow.call(receiver)).receiver!==capture)throw Error('lexical receiver');
        \\let got=0,called=0;const thenable={get then(){got++;return resolve=>{called++;resolve(19)}}};const outer=returnEcho(thenable);if(got!==1||called!==0)throw Error('adoption order');if(await outer!==19||called!==1)throw Error('thenable adoption');
        \\const inner=Promise.resolve(23),adopted=returnEcho(inner);if(inner===adopted||await adopted!==23)throw Error('distinct outer Promise');
    , "agent-return-adoption.mjs");
}

test "native Agent return adapter ordinary synchronous throw becomes rejected same reason" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    try s.put(try global(&s), "returnThrow", try s.own(try returned.create(engine, "returnThrow", 1, thrower, &.{})));
    try run(engine,
        \\const reason={};let outer;try{outer=returnThrow(reason)}catch(e){throw Error('escaped synchronously')};let caught=false;try{await outer}catch(e){caught=e===reason}if(!caught)throw Error('reason identity');
    , "agent-return-throw.mjs");
}

test "native Agent return adapter marked private rejected DATA is adopted without reclassification" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    try std.testing.expectError(error.JavaScriptException, engine.checked(engine.throwNativeOutOfMemory()));
    const reason = engine.captured_exception orelse return error.MissingNativeReason;
    c.JS_SetUncatchableError(engine.context, reason);
    const generation = c.pi_js_native_allocation_error_generation(reason);
    try std.testing.expect(generation != 0);
    const g = try global(&s); try s.put(g, "rejectedData", reason);
    try s.put(g, "returnEcho", try s.own(try returned.create(engine, "returnEcho", 1, echo, &.{})));
    try run(engine,
        \\const rejected=Promise.reject(rejectedData);let outer;try{outer=returnEcho(rejected)}catch(e){throw Error('DATA synchronously escaped')};let same=false;try{await outer}catch(e){same=e===rejectedData}if(!same)throw Error('rejected DATA identity');
    , "agent-return-rejected-data.mjs");
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(generation, c.pi_js_native_allocation_error_generation(reason));
}

fn hostOOM(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return error.OutOfMemory;
}
test "native Agent return adapter direct trusted native failure escapes rather than rejection DATA" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const function = try returned.create(engine, "directHostFailure", 0, hostOOM, &.{}); defer engine.freeValue(function);
    const result = c.JS_Call(engine.context, function, c.pi_js_undefined(), 0, null); defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsException(result));
    try std.testing.expect(c.JS_HasException(engine.context));
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
}

test "native Agent return adapter production emitter ignores push return and rejects getter throw" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const stream = try s.own(try engine.eval("({push(event){this.event=event;return {get then(){throw Error('push return must be ignored')}}}})", "agent-emitter-stream.js", c.JS_EVAL_TYPE_GLOBAL));
    const g = try global(&s); try s.put(g, "stream", stream);
    const emitter = try s.own(try @import("extensions/native_agent_stream.zig").createEmitter(engine, stream));
    try std.testing.expect(c.JS_IsAsyncFunction(emitter));
    try s.put(g, "emit", emitter);
    try run(engine,
        \\const event={};if(await emit(event)!==undefined||stream.event!==event)throw Error('emitter semantics');
        \\const reason={};Object.defineProperty(stream,'push',{get(){throw reason}});let promise;try{promise=emit(event)}catch(e){throw Error('getter escaped synchronously')};let same=false;try{await promise}catch(e){same=e===reason}if(!same)throw Error('push getter identity');
    , "agent-emitter-production.mjs");
}

test "native Agent return adapter production runToolCall suspends and preserves options getter order" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const function = try s.own(try @import("extensions/native_agent_single_tool.zig").create(engine));
    try std.testing.expect(c.JS_IsAsyncFunction(function));
    try s.put(try global(&s), "runToolCall", function);
    try run(engine,
        \\const reads=[],marker={};const options={get assistantMessage(){reads.push('assistant');return{}},get context(){reads.push('context');return{}},get signal(){reads.push('signal');return undefined},get tools(){reads.push('tools');return[]}};
        \\const call={id:'1',name:'missing',arguments:{}};const promise=runToolCall(call,options);if(reads.join(',')!=='assistant,context,signal,tools')throw Error('getter order');const outcome=await promise;if(outcome.toolCall!==call||outcome.isError!==true)throw Error('immediate branch');
        \\let rejected;try{rejected=runToolCall(call,{get assistantMessage(){throw marker}})}catch(e){throw Error('sync options throw')};let same=false;try{await rejected}catch(e){same=e===marker}if(!same)throw Error('options reason');
    , "agent-run-tool-call-production.mjs");
}

const CleanupMode = enum { ordinary, raw_private, fatal_pending, fatal_captured };
const CleanupState = struct { engine: *em.Engine, first: c.JSValue, cleanup: c.JSValue, mode: CleanupMode };
var cleanup_mode: CleanupMode = .ordinary;
var cleanup_observed: ?c.JSValue = null;
var retain_first_cleanup = false;
var first_cleanup_observed: ?c.JSValue = null;
var cleanup_finalized: usize = 0;
fn recordCleanup(engine: *em.Engine, reason: c.JSValue) void {
    if (retain_first_cleanup and first_cleanup_observed == null) first_cleanup_observed = c.JS_DupValue(engine.context, reason);
    if (cleanup_observed) |old| engine.freeValue(old);
    cleanup_observed = c.JS_DupValue(engine.context, reason);
    cleanup_finalized += 1;
}
fn cleanupCall(_: ?*c.JSContext, function: c.JSValue, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int) callconv(.c) c.JSValue {
    const state: *CleanupState = @ptrCast(@alignCast(c.JS_GetOpaque(function, c.JS_GetClassID(function)).?));
    return c.JS_Throw(state.engine.context, c.JS_DupValue(state.engine.context, state.first));
}
fn cleanupMark(runtime: ?*c.JSRuntime, object: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *CleanupState = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    c.JS_MarkValue(runtime, state.first, visit); c.JS_MarkValue(runtime, state.cleanup, visit);
}
fn cleanupFinalizer(_: ?*c.JSRuntime, object: c.JSValue) callconv(.c) void {
    const state: *CleanupState = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    const engine = state.engine;
    switch (state.mode) {
        .ordinary => { _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, state.cleanup)); },
        .raw_private => { _ = engine.throwNativeOutOfMemory(); },
        .fatal_pending => { _ = engine.throwNativeOutOfMemoryFatal(); },
        .fatal_captured => {
            const value = engine.checked(engine.throwNativeOutOfMemoryFatal()) catch c.pi_js_undefined();
            engine.freeValue(value);
        },
    }
    if (c.JS_HasException(engine.context)) {
        const reason = c.JS_GetException(engine.context);
        recordCleanup(engine, reason);
        _ = c.JS_Throw(engine.context, reason);
    } else if (engine.captured_exception) |reason| recordCleanup(engine, reason);
    engine.freeValue(state.first); engine.freeValue(state.cleanup); engine.gpa.destroy(state);
}
fn makeCleanup(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var class: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Sole owned test cleanup callable", .call = cleanupCall, .finalizer = cleanupFinalizer, .gc_mark = cleanupMark };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const object = try engine.checked(c.JS_NewObjectClass(engine.context, class)); errdefer engine.freeValue(object);
    const state = try engine.gpa.create(CleanupState);
    state.* = .{ .engine = engine, .first = c.JS_DupValue(engine.context, roots[0]), .cleanup = c.JS_DupValue(engine.context, roots[1]), .mode = cleanup_mode };
    _ = c.JS_SetOpaque(object, state);
    return object;
}

test "native Agent return adapter production sole callable cleanup preserves first ordinary error" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    defer { if (cleanup_observed) |reason| engine.freeValue(reason); cleanup_observed = null; }
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    cleanup_mode = .ordinary;
    const g = try global(&s); const first = try s.object(); const second = try s.object();
    try s.put(g, "first", first); try s.put(g, "second", second);
    try s.put(g, "makeCleanup", try s.own(try functions.createArrow(engine, "makeCleanup", 0, makeCleanup, &.{ first, second })));
    const stream = try s.own(try engine.eval("({get push(){return makeCleanup()}})", "sole-cleanup-stream.js", c.JS_EVAL_TYPE_GLOBAL));
    try s.put(g, "emitCleanup", try s.own(try @import("extensions/native_agent_stream.zig").createEmitter(engine, stream)));
    try run(engine,
        \\let same=false;try{await emitCleanup({})}catch(e){same=e===first}if(!same)throw Error('ordinary first completion replaced');
    , "agent-sole-cleanup-ordinary.mjs");
    try std.testing.expect(cleanup_observed != null);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, cleanup_observed.?, second));
}

test "native Agent return adapter production per release raw and recorded cleanup fatal precede ordinary error" {
    for ([_]CleanupMode{ .raw_private, .fatal_pending, .fatal_captured }) |mode| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        defer { if (cleanup_observed) |reason| engine.freeValue(reason); cleanup_observed = null; }
        var s: Scope = .{ .engine = engine }; defer s.deinit();
        cleanup_mode = mode;
        const first = try s.object(); const second = try s.object(); const g = try global(&s);
        try s.put(g, "makeCleanup", try s.own(try functions.createArrow(engine, "makeCleanup", 0, makeCleanup, &.{ first, second })));
        const stream = try s.own(try engine.eval("({get push(){return makeCleanup()}})", "fatal-cleanup-stream.js", c.JS_EVAL_TYPE_GLOBAL));
        const emitter = try s.own(try @import("extensions/native_agent_stream.zig").createEmitter(engine, stream));
        const result = c.JS_Call(engine.context, emitter, c.pi_js_undefined(), 0, null); defer engine.freeValue(result);
        try std.testing.expect(c.JS_IsException(result));
        try std.testing.expect(c.JS_HasException(engine.context));
        const actual = c.JS_GetException(engine.context); defer engine.freeValue(actual);
        try std.testing.expect(cleanup_observed != null and c.JS_IsStrictEqual(engine.context, actual, cleanup_observed.?));
        try std.testing.expect(c.JS_IsUncatchableError(actual));
        try std.testing.expect(c.pi_js_native_allocation_error_generation(actual) != 0);
    }
}

test "native Agent return adapter production runToolCall escrows getter failure before sole earlier value cleanup" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    defer { if (cleanup_observed) |reason| engine.freeValue(reason); cleanup_observed = null; }
    var s: Scope = .{ .engine = engine }; defer s.deinit(); cleanup_mode = .ordinary;
    const g = try global(&s); const first = try s.object(); const second = try s.object();
    try s.put(g, "first", first);
    try s.put(g, "makeCleanup", try s.own(try functions.createArrow(engine, "makeCleanup", 0, makeCleanup, &.{ first, second })));
    try s.put(g, "runToolCall", try s.own(try @import("extensions/native_agent_single_tool.zig").create(engine)));
    try run(engine,
        \\const options={get assistantMessage(){return makeCleanup()},get context(){throw first}};let same=false;try{await runToolCall({},options)}catch(e){same=e===first}if(!same)throw Error('options completion replaced during cleanup');
    , "agent-tool-getter-cleanup.mjs");
    try std.testing.expect(cleanup_observed != null and c.JS_IsStrictEqual(engine.context, cleanup_observed.?, second));
}

var append_failure: ?*std.testing.FailingAllocator = null;
fn pushOwnedCleanup(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const result = try makeCleanup(engine, receiver, args, roots);
    const allocator = append_failure.?;
    // The real guest call has produced the sole-owned result. Only the next
    // Scope.own growth is failed; neither a VM allocation nor a mock reason.
    allocator.fail_index = allocator.alloc_index;
    allocator.resize_fail_index = allocator.resize_index;
    return result;
}
test "native Agent return adapter actual Scope call append OOM is not downgraded by sole result cleanup" {
    for ([_]CleanupMode{ .ordinary, .fatal_pending, .fatal_captured }) |mode| {
        var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const engine = try em.Engine.init(allocator.allocator(), .{}); defer engine.deinit();
        defer { if (cleanup_observed) |reason| engine.freeValue(reason); cleanup_observed = null; append_failure = null; }
        var s: Scope = .{ .engine = engine }; defer s.deinit();
        cleanup_mode = mode; append_failure = &allocator;
        const first = try s.object(); const second = try s.object();
        const push = try s.own(try functions.createArrow(engine, "push", 0, pushOwnedCleanup, &.{ first, second }));
        var temporaries: Scope = .{ .engine = engine };
        _ = try temporaries.own(c.pi_js_undefined());
        while (temporaries.values.items.len < temporaries.values.capacity) _ = try temporaries.own(c.pi_js_undefined());
        var invocation: em.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
        engine.native_exception_diagnostics_suppressed += 1;
        const completed = @import("extensions/native_agent_af_completion.zig").finishValue(&temporaries, temporaries.call(push, c.pi_js_undefined(), &.{})) catch |err| blk: {
            std.debug.assert(err == error.JavaScriptException);
            break :blk engine.throwCaptured();
        };
        engine.native_exception_diagnostics_suppressed -= 1;
        allocator.fail_index = std.math.maxInt(usize); allocator.resize_fail_index = std.math.maxInt(usize);
        const result = engine.leaveNativeInvocation(&invocation, completed); defer engine.freeValue(result);
        try std.testing.expect(allocator.has_induced_failure);
        try std.testing.expect(c.JS_IsException(result) and c.JS_HasException(engine.context));
        const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
        try std.testing.expect(c.JS_IsUncatchableError(reason));
        try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
        try std.testing.expect(cleanup_observed != null);
        if (mode == .ordinary) {
            try std.testing.expect(!c.JS_IsStrictEqual(engine.context, reason, cleanup_observed.?));
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, second, cleanup_observed.?));
        } else try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, cleanup_observed.?));
    }
}

test "native Agent return adapter raw first cleanup fatal is published before later recorded producer" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    defer {
        if (cleanup_observed) |reason| engine.freeValue(reason); cleanup_observed = null;
        if (first_cleanup_observed) |reason| engine.freeValue(reason); first_cleanup_observed = null;
        retain_first_cleanup = false;
    }
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const ordinary = try s.object(); const ignored = try s.object();
    var retired: Scope = .{ .engine = engine }; defer retired.deinit();
    cleanup_mode = .raw_private;
    _ = try retired.own(try makeCleanup(engine, c.pi_js_undefined(), &.{}, &.{ ordinary, ignored }));
    cleanup_mode = .fatal_pending;
    _ = try retired.own(try makeCleanup(engine, c.pi_js_undefined(), &.{}, &.{ ordinary, ignored }));
    retain_first_cleanup = true; cleanup_finalized = 0;
    var invocation: em.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    engine.native_exception_diagnostics_suppressed += 1;
    const result_action = @import("extensions/native_agent_af_completion.zig").finishAction(&retired, .{ .thrown = c.JS_DupValue(engine.context, ordinary) });
    const raw = if (result_action) |action| switch (action) {
        .thrown => |reason| c.JS_Throw(engine.context, reason),
        .returned, .awaited => |value| value,
    } else |err| blk: {
        std.debug.assert(err == error.JavaScriptException);
        break :blk engine.throwCaptured();
    };
    engine.native_exception_diagnostics_suppressed -= 1;
    const result = engine.leaveNativeInvocation(&invocation, raw); defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsException(result) and c.JS_HasException(engine.context));
    const actual = c.JS_GetException(engine.context); defer engine.freeValue(actual);
    try std.testing.expectEqual(@as(usize, 2), cleanup_finalized);
    try std.testing.expect(first_cleanup_observed != null and cleanup_observed != null);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, first_cleanup_observed.?));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, cleanup_observed.?));
    try std.testing.expect(c.JS_IsUncatchableError(actual));
}

test "native Agent return adapter captured only marked reason cannot become current producer" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try std.testing.expectError(error.JavaScriptException, engine.checked(engine.throwNativeOutOfMemory()));
    const old = engine.captured_exception orelse return error.MissingReason;
    c.JS_SetUncatchableError(engine.context, old);
    const generation = c.pi_js_native_allocation_error_generation(old);
    var scope: Scope = .{ .engine = engine };
    var invocation: em.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    defer if (invocation.active) {
        const value = engine.leaveNativeInvocation(&invocation, c.pi_js_undefined());
        engine.freeValue(value);
    };
    const action = try @import("extensions/native_agent_af_completion.zig").finishAction(&scope, error.JavaScriptException);
    switch (action) {
        .thrown => |reason| {
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, old));
            engine.freeValue(reason);
        },
        .returned, .awaited => |value| { engine.freeValue(value); return error.UnexpectedCapturedDataAction; },
    }
    const result = engine.leaveNativeInvocation(&invocation, c.pi_js_undefined()); defer engine.freeValue(result);
    try std.testing.expect(!c.JS_IsException(result) and !c.JS_HasException(engine.context));
    try std.testing.expect(c.JS_IsUncatchableError(old));
    try std.testing.expectEqual(generation, c.pi_js_native_allocation_error_generation(old));
}

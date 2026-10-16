const std = @import("std");
const em = @import("extensions/engine.zig");
const af = @import("extensions/native_async_function.zig");
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const c = em.c;
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn trace(scope: *Scope, args: []const c.JSValue, label: []const u8) !void {
    const target = argument(args, 1);
    if (!c.JS_IsUndefined(target) and !c.JS_IsNull(target)) _ = try scope.invoke(target, "push", &.{try scope.text(label)});
}
fn echo(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try trace(&scope, args, "body");
    return c.JS_DupValue(engine.context, argument(args, 0));
}
fn thrower(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, argument(args, 0))));
}
fn reflect(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const output = try scope.object();
    const values = try scope.array();
    for (args, 0..) |value, i| try scope.index(values, @intCast(i), value);
    try scope.put(output, "thisValue", receiver);
    try scope.put(output, "args", values);
    return c.JS_DupValue(engine.context, output);
}
fn arrow(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const output = try scope.object();
    try scope.put(output, "thisValue", receiver);
    try scope.put(output, "value", argument(args, 0));
    return c.JS_DupValue(engine.context, output);
}
fn awaited(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, _: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (completion) {
        .start => {
            try trace(&scope, args, "start");
            return .{ .awaited = c.JS_DupValue(engine.context, argument(args, 0)) };
        },
        .fulfilled => {
            try trace(&scope, args, "resumed");
            return .{ .returned = c.JS_DupValue(engine.context, input) };
        },
        .rejected => {
            if (c.JS_ToBool(engine.context, roots[0]) != 1) return .{ .thrown = c.JS_DupValue(engine.context, input) };
            try trace(&scope, args, "caught");
            const result = try scope.object();
            try scope.put(result, "caught", input);
            return .{ .returned = c.JS_DupValue(engine.context, result) };
        },
    }
}
fn stateful(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) {
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const local = try scope.object();
        try scope.put(local, "tag", try scope.text("private-local"));
        af.replaceState(engine, state, c.JS_DupValue(engine.context, local));
        return .{ .awaited = c.JS_DupValue(engine.context, argument(args, 0)) };
    }
    return if (completion == .fulfilled) .{ .returned = c.JS_DupValue(engine.context, state.*) } else .{ .thrown = c.JS_DupValue(engine.context, input) };
}
fn brand(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_bool(context, @intFromBool(argc > 0 and c.JS_IsAsyncFunction(argv[0])));
}
fn runGC(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    c.JS_RunGC(c.JS_GetRuntime(context));
    return c.pi_js_undefined();
}
fn otherBody(context: ?*c.JSContext, _: c.JSValue, _: c.JSValue, _: c_int, _: [*c]const c.JSValue, _: c_int, _: c.JSValue, _: [*c]c.JSValue, action: [*c]c_int) callconv(.c) c.JSValue {
    action[0] = c.JS_PI_AF_RETURN;
    const global = c.JS_GetGlobalObject(context);
    defer c.JS_FreeValue(context, global);
    return c.JS_GetPropertyStr(context, global, "realmMarker");
}
fn install(engine: *em.Engine) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const functions = try scope.object();
    const lexical = try scope.object();
    try scope.put(lexical, "tag", try scope.text("lexical"));
    try scope.put(global, "asyncFixtureLexical", lexical);
    try scope.put(functions, "echo", try scope.own(try af.create(engine, "echo", 2, echo, &.{})));
    try scope.put(functions, "thrower", try scope.own(try af.create(engine, "thrower", 1, thrower, &.{})));
    try scope.put(functions, "reflect", try scope.own(try af.create(engine, "reflect", 0, reflect, &.{})));
    try scope.put(functions, "arrow", try scope.own(try af.createArrow(engine, "arrow", 1, arrow, &.{}, lexical)));
    try scope.put(functions, "awaiter", try scope.own(try af.createResumable(engine, "awaiter", 2, awaited, &.{c.pi_js_bool(engine.context, 0)})));
    try scope.put(functions, "catcher", try scope.own(try af.createResumable(engine, "catcher", 2, awaited, &.{c.pi_js_bool(engine.context, 1)})));
    try scope.put(functions, "stateful", try scope.own(try af.createResumable(engine, "stateful", 1, stateful, &.{})));
    try scope.put(global, "asyncFixtures", functions);
    try scope.put(global, "isAsyncFunction", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, brand, "isAsyncFunction", 1))));
    try scope.put(global, "runGC", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, runGC, "runGC", 0))));
    const other = c.JS_NewContext(engine.runtime) orelse return error.OutOfMemory;
    defer c.JS_FreeContext(other);
    const otherGlobal = c.JS_GetGlobalObject(other);
    defer c.JS_FreeValue(other, otherGlobal);
    if (c.JS_DefinePropertyValueStr(other, otherGlobal, "realmMarker", c.JS_NewInt32(other, 42), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    const promise = c.JS_GetPropertyStr(other, otherGlobal, "Promise");
    defer c.JS_FreeValue(other, promise);
    const prototype = c.JS_GetPropertyStr(other, promise, "prototype");
    defer c.JS_FreeValue(other, prototype);
    try scope.put(global, "otherPromisePrototype", prototype);
    const otherFunction = c.JS_PiNewNativeAsyncFunction(other, otherBody, c.pi_js_undefined(), c.pi_js_undefined(), 0, "otherAsync", 0);
    if (c.JS_IsException(otherFunction)) return error.JavaScriptException;
    defer c.JS_FreeValue(other, otherFunction);
    try scope.put(global, "otherAsync", otherFunction);
}
test "native async body proposal matches genuine Node observations after independent review and Source capture" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const expected = @embedFile("extensions/fixtures/async-function-body-node24.json");
    const data = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "async-function-body-node24.json")));
    try scope.put(try scope.own(c.JS_GetGlobalObject(engine.context)), "asyncBodySource", data);
    const value = engine.evalModule(@embedFile("extensions/fixtures/async-function-body-node24.input.txt") ++ "\nif(asyncBodySource.runtime!=='v24.14.0'||asyncBodyRows.length!==asyncBodySource.rows.length)throw Error('Source authority');const mismatches=[];for(let i=0;i<asyncBodyRows.length;i++)if(JSON.stringify(asyncBodyRows[i])!==JSON.stringify(asyncBodySource.rows[i]))mismatches.push({case:i,actual:asyncBodyRows[i],expected:asyncBodySource.rows[i]});if(mismatches.length)throw Error(JSON.stringify(mismatches));", "native-async-body-source.mjs") catch |err| {
        std.debug.print("Native async body proposal: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    engine.freeValue(value);
    c.JS_RunGC(engine.runtime);
}
test "native async body proposal genuine brand strict receiver outer Promise and native toString" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const value = try engine.evalModule(
        \\const f=asyncFixtures.echo;if(!isAsyncFunction(f)||Object.prototype.toString.call(f)!=='[object AsyncFunction]'||Object.hasOwn(f,'prototype'))throw Error('genuine async brand');const inner=Promise.resolve(7),outer=f(inner);if(outer===inner||await outer!==7)throw Error('real outer promise');const before=Function.prototype.toString.call(f);if(before!=='function echo() { [native code] }')throw Error('native source representation');Object.defineProperty(f,'name',{get(){throw Error('must not read name')},configurable:true});if(Function.prototype.toString.call(f)!==before)throw Error('native source name drift');const receiver={},r=await asyncFixtures.reflect.call(receiver,1,2);if(r.thisValue!==receiver||r.args.join(',')!=='1,2')throw Error('strict receiver/args');export const proved=true;
    , "native-async-body-brand.mjs");
    engine.freeValue(value);
}
fn hostOOM(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return error.OutOfMemory;
}
test "native async body proposal raw host OOM remains uncatchable rather than rejected Promise" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const function = try af.create(engine, "hostOOM", 0, hostOOM, &.{});
    defer engine.freeValue(function);
    const result = c.JS_Call(engine.context, function, c.pi_js_undefined(), 0, null);
    defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsException(result));
    const failure = c.JS_GetException(engine.context);
    defer engine.freeValue(failure);
    try std.testing.expect(c.JS_IsUncatchableError(failure));
}

test "native async body proposal Zig host allocation failures release captures and callbacks" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            install(engine) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule(
                \\const marker={},inner=Promise.resolve(marker);if(await asyncFixtures.echo(inner)!==marker)throw Error('return alias');if(await asyncFixtures.awaiter(inner)!==marker)throw Error('await alias');let resolve;const gate=new Promise(r=>resolve=r),local=asyncFixtures.stateful(gate);runGC();resolve(1);if((await local).tag!=='private-local')throw Error('local roots');const raw={};try{await asyncFixtures.thrower(raw);throw Error('missing raw')}catch(e){if(e!==raw)throw e}export const done=true;
            , "native-async-body-host-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}

fn stackProjection(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const frames = try scope.own(try engine.checked(c.JS_CaptureCurrentStackFrames(engine.context, 1, c.pi_js_undefined(), null, -1, -1, 0)));
    const first = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, frames, 0)));
    var filename: c.JSValue = undefined;
    var name: c.JSValue = undefined;
    var line: c_int = undefined;
    var column: c_int = undefined;
    var native: c_int = undefined;
    var constructor: c_int = undefined;
    if (c.JS_ReadCapturedStackFrame(engine.context, first, &filename, &name, &line, &column, &native, &constructor) < 0) return error.InvalidCapturedFrame;
    _ = try scope.own(filename);
    _ = try scope.own(name);
    const output = try scope.object();
    try scope.put(output, "name", name);
    try scope.put(output, "filename", filename);
    try scope.put(output, "line", c.JS_NewInt32(engine.context, line));
    try scope.put(output, "column", c.JS_NewInt32(engine.context, column));
    try scope.put(output, "native", c.pi_js_bool(engine.context, native));
    try scope.put(output, "constructor", c.pi_js_bool(engine.context, constructor));
    return c.JS_DupValue(engine.context, output);
}
fn stackBody(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, completion: af.Completion, _: c.JSValue) !af.Action {
    if (completion == .start) {
        af.replaceState(engine, state, try stackProjection(engine));
        return .{ .awaited = c.pi_js_undefined() };
    }
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const output = try scope.array();
    try scope.index(output, 0, state.*);
    try scope.index(output, 1, try scope.own(try stackProjection(engine)));
    return .{ .returned = c.JS_DupValue(engine.context, output) };
}
test "native async body proposal stack capture preserves native name on start and resume" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const function = try scope.own(try af.createResumable(engine, "stackBody", 0, stackBody, &.{}));
    try scope.put(try scope.own(c.JS_GetGlobalObject(engine.context)), "stackBody", function);
    const result = try engine.evalModule(
        \\for(const frame of await stackBody()){if(frame.name!=='stackBody'||frame.native!==true||frame.constructor!==false||frame.filename!==null||frame.line!==-1||frame.column!==-1)throw Error(JSON.stringify(frame))}export const done=true;
    , "native-async-body-stack.mjs");
    engine.freeValue(result);
}
fn resumedOOM(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue, _: *c.JSValue, completion: af.Completion, _: c.JSValue) !af.Action {
    if (completion == .start) return .{ .awaited = c.pi_js_undefined() };
    return error.OutOfMemory;
}
test "native async body proposal resumed native OOM escapes the job without Promise rejection" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const function = try af.createResumable(engine, "resumedOOM", 0, resumedOOM, &.{});
    defer engine.freeValue(function);
    const pending = try engine.checked(c.JS_Call(engine.context, function, c.pi_js_undefined(), 0, null));
    defer engine.freeValue(pending);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, pending));
    var context: ?*c.JSContext = null;
    try std.testing.expect(c.JS_ExecutePendingJob(engine.runtime, &context) < 0);
    const failure = c.JS_GetException(context orelse engine.context);
    defer engine.freeValue(failure);
    try std.testing.expect(c.JS_IsUncatchableError(failure));
    try std.testing.expect(engine.native_allocation_exception != null);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, failure, engine.native_allocation_exception.?));
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, pending));
    c.JS_RunGC(engine.runtime);
}
test "native async body proposal ordinary bound proxy and revoked callable source never read guest name" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const result = try engine.evalModule(
        \\function ordinary(value){return value}const source=Function.prototype.toString.call(ordinary),bound=ordinary.bind(null,7),proxy=new Proxy(ordinary,{get(){throw Error('proxy get must not run')}}),pair=Proxy.revocable(ordinary,{});pair.revoke();Object.defineProperty(bound,'name',{get(){throw Error('bound name must not run')},configurable:true});for(const fn of[bound,proxy,pair.proxy])if(Function.prototype.toString.call(fn)!=='function () { [native code] }')throw Error('wrapper source');if(bound()!==7||proxy(8)!==8||Function.prototype.toString.call(ordinary)!==source)throw Error('ordinary function changed');let threw=false;try{pair.proxy()}catch(e){threw=e instanceof TypeError}if(!threw)throw Error('revoked call');for(const value of[{},new Proxy({},{}),null]){let rejected=false;try{Function.prototype.toString.call(value)}catch(e){rejected=e instanceof TypeError}if(!rejected)throw Error('noncallable accepted')}export const done=true;
    , "native-async-body-wrapper-source.mjs");
    engine.freeValue(result);
}
fn rawEcho(context: ?*c.JSContext, _: c.JSValue, _: c.JSValue, argc: c_int, argv: [*c]const c.JSValue, _: c_int, _: c.JSValue, _: [*c]c.JSValue, action: [*c]c_int) callconv(.c) c.JSValue {
    action[0] = c.JS_PI_AF_RETURN;
    return c.JS_DupValue(context, if (argc > 0) argv[0] else c.pi_js_undefined());
}
test "native async body proposal genuine C factory call and argument pressure failures remain reusable" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    defer c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
    c.JS_SetMemoryLimit(engine.runtime, 1);
    const failed_factory = c.JS_PiNewNativeAsyncFunction(engine.context, rawEcho, c.pi_js_undefined(), c.pi_js_undefined(), 0, "rawEcho", 1);
    c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
    try std.testing.expect(c.JS_IsException(failed_factory));
    engine.freeValue(c.JS_GetException(engine.context));
    const function = try engine.checked(c.JS_PiNewNativeAsyncFunction(engine.context, rawEcho, c.pi_js_undefined(), c.pi_js_undefined(), 0, "rawEcho", 1));
    defer engine.freeValue(function);
    c.JS_SetMemoryLimit(engine.runtime, 1);
    const failed_call = c.JS_Call(engine.context, function, c.pi_js_undefined(), 0, null);
    c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
    try std.testing.expect(c.JS_IsException(failed_call));
    engine.freeValue(c.JS_GetException(engine.context));
    // The 64 KiB copied argument vector exceeds the 16 KiB allowance even
    // after the invocation state and intrinsic capability have been created.
    var arguments: [4096]c.JSValue = undefined;
    for (&arguments) |*value| value.* = c.pi_js_undefined();
    var usage: c.JSMemoryUsage = undefined;
    c.JS_RunGC(engine.runtime);
    c.JS_ComputeMemoryUsage(engine.runtime, &usage);
    c.JS_SetMemoryLimit(engine.runtime, @as(usize, @intCast(usage.malloc_size)) + 16 * 1024);
    const failed_arguments = c.JS_Call(engine.context, function, c.pi_js_undefined(), arguments.len, &arguments);
    c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
    try std.testing.expect(c.JS_IsException(failed_arguments));
    engine.freeValue(c.JS_GetException(engine.context));
    const retried = try engine.checked(c.JS_Call(engine.context, function, c.pi_js_undefined(), 1, &arguments));
    defer engine.freeValue(retried);
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, retried));
    try std.testing.expect(!c.JS_HasException(engine.context));
    c.JS_RunGC(engine.runtime);
}
fn armAwaitOOM(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    c.JS_SetMemoryLimit(c.JS_GetRuntime(context), 1);
    return c.JS_DupValue(context, roots[0]);
}
fn catchAwaitOOM(context: ?*c.JSContext, captures: c.JSValue, _: c.JSValue, _: c_int, argv: [*c]const c.JSValue, completion: c_int, input: c.JSValue, _: [*c]c.JSValue, action: [*c]c_int) callconv(.c) c.JSValue {
    if (completion == c.JS_PI_AF_START) {
        action[0] = c.JS_PI_AF_AWAIT;
        return c.JS_DupValue(context, argv[0]);
    }
    if (completion != c.JS_PI_AF_AWAIT_REJECTED) return c.JS_ThrowInternalError(context, "Expected allocation failure at await");
    // Updating the pre-existing data property requires no new VM allocation.
    if (c.JS_SetPropertyStr(context, captures, "caught", c.pi_js_bool(context, 1)) < 0) return c.JS_Throw(context, c.JS_GetException(context));
    action[0] = c.JS_PI_AF_RETURN;
    return c.JS_DupValue(context, input);
}
test "native async body proposal actual C await handler allocation failure reaches native catch and retires" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    defer c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const captures = try scope.object();
    try scope.put(captures, "caught", c.pi_js_bool(engine.context, 0));
    const function = try scope.own(try engine.checked(c.JS_PiNewNativeAsyncFunction(engine.context, catchAwaitOOM, captures, c.pi_js_undefined(), 0, "catcher", 1)));
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    var roots = [_]c.JSValue{try scope.get(global, "Promise")};
    const input = try scope.own(try engine.checked(c.JS_NewSettledPromise(engine.context, false, c.pi_js_undefined())));
    const getter = try engine.checked(c.JS_NewCFunctionData2(engine.context, armAwaitOOM, "get constructor", 0, 0, roots.len, &roots));
    const atom = c.JS_NewAtom(engine.context, "constructor");
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, input, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
    var args = [_]c.JSValue{input};
    // PromiseResolve reuses input. Its constructor getter closes the heap
    // before js_async_function_resolve_create allocates continuation objects.
    const pending = c.JS_Call(engine.context, function, c.pi_js_undefined(), args.len, &args);
    c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
    defer engine.freeValue(pending);
    try std.testing.expect(!c.JS_IsException(pending));
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, pending));
    try std.testing.expect(c.JS_ToBool(engine.context, try scope.get(captures, "caught")) == 1);
    const failure = c.JS_PromiseResult(engine.context, pending);
    defer engine.freeValue(failure);
    try std.testing.expect(!c.JS_IsUndefined(failure));
    try std.testing.expect(!c.JS_HasException(engine.context));
    c.JS_RunGC(engine.runtime);
}

fn armAwaitBudget(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, budget: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    var usage: c.JSMemoryUsage = undefined;
    c.JS_ComputeMemoryUsage(c.JS_GetRuntime(context), &usage);
    c.JS_SetMemoryLimit(c.JS_GetRuntime(context), @as(usize, @intCast(usage.malloc_size)) + @as(usize, @intCast(budget)) + 1);
    return c.JS_DupValue(context, roots[0]);
}
fn budgetAwait(context: ?*c.JSContext, captures: c.JSValue, receiver: c.JSValue, argc: c_int, argv: [*c]const c.JSValue, completion: c_int, input: c.JSValue, state: [*c]c.JSValue, action: [*c]c_int) callconv(.c) c.JSValue {
    if (completion == c.JS_PI_AF_AWAIT_FULFILLED) {
        action[0] = c.JS_PI_AF_RETURN;
        return c.JS_DupValue(context, input);
    }
    return catchAwaitOOM(context, captures, receiver, argc, argv, completion, input, state, action);
}
test "native async body proposal bounded C continuation reaction and job allocation pressure never loses suspension" {
    var caught: usize = 0;
    var suspended: usize = 0;
    // A settled input crosses continuation creation, two reaction allocations,
    // and job enqueue. Fine-grained quotas test those successive C allocations,
    // independently of the Zig GPA fault-injection test.
    for (0..129) |step| {
        const engine = try em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        defer c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const captures = try scope.object();
        try scope.put(captures, "caught", c.pi_js_bool(engine.context, 0));
        const function = try scope.own(try engine.checked(c.JS_PiNewNativeAsyncFunction(engine.context, budgetAwait, captures, c.pi_js_undefined(), 0, "budgetAwait", 1)));
        const global = try scope.own(c.JS_GetGlobalObject(engine.context));
        var roots = [_]c.JSValue{try scope.get(global, "Promise")};
        const input = try scope.own(try engine.checked(c.JS_NewSettledPromise(engine.context, false, c.pi_js_undefined())));
        const getter = try engine.checked(c.JS_NewCFunctionData2(engine.context, armAwaitBudget, "get constructor", 0, @intCast(step * 16), roots.len, &roots));
        const atom = c.JS_NewAtom(engine.context, "constructor");
        defer c.JS_FreeAtom(engine.context, atom);
        if (c.JS_DefinePropertyGetSet(engine.context, input, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
        var args = [_]c.JSValue{input};
        const pending = c.JS_Call(engine.context, function, c.pi_js_undefined(), args.len, &args);
        c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
        defer engine.freeValue(pending);
        try std.testing.expect(!c.JS_IsException(pending));
        try std.testing.expect(!c.JS_HasException(engine.context));
        if (c.JS_PromiseState(engine.context, pending) == c.JS_PROMISE_PENDING) {
            suspended += 1;
            try std.testing.expect(c.JS_IsJobPending(engine.runtime));
            _ = try engine.runReadyJobs(8);
        }
        try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, pending));
        if (c.JS_ToBool(engine.context, try scope.get(captures, "caught")) == 1) caught += 1;
        try std.testing.expect(!c.JS_HasException(engine.context));
        c.JS_RunGC(engine.runtime);
    }
    try std.testing.expect(caught > 0 and suspended > 0);
}

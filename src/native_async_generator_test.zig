const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const sdk = @import("extensions/native_sdk.zig");
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const gen = @import("extensions/native_async_generator.zig");
const c = em.c;
fn completeBody(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: c.JSValue, action: [*c]c_int) callconv(.c) c.JSValue {
    action[0] = c.JS_PI_AG_COMPLETE;
    return c.pi_js_undefined();
}
fn equal(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return scope.equal(value, try scope.text(text));
}
fn advance(engine: *em.Engine, owner: c.JSValue, completion: gen.Completion, value: c.JSValue) !gen.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    // Real host-allocation failure inside a resume must traverse the C queue
    // as the original tagged native OOM, not as an unrelated Error message.
    const probe = try engine.gpa.alloc(u8, 1);
    defer engine.gpa.free(probe);
    _ = try scope.invoke(try scope.get(owner, "calls"), "push", &.{try scope.text(@tagName(completion))});
    const mode = try scope.get(owner, "mode");
    if (try equal(&scope, mode, "vm-oom")) {
        const payload = c.JS_DupValue(engine.context, try scope.get(owner, "input"));
        c.JS_SetMemoryLimit(engine.runtime, 0);
        return .{ .complete = payload };
    }
    switch (completion) {
        .start => {
            if (try equal(&scope, mode, "await")) return .{ .awaited = c.JS_DupValue(engine.context, try scope.get(owner, "input")) };
            return .{ .yielded = c.JS_DupValue(engine.context, try scope.get(owner, "input")) };
        },
        .fulfilled => return .{ .yielded = c.JS_DupValue(engine.context, value) },
        .rejected => return .{ .thrown = c.JS_DupValue(engine.context, value) },
        .next => return .{ .returned = c.JS_DupValue(engine.context, try scope.get(owner, "final")) },
        .returned => {
            try scope.put(owner, "closed", c.pi_js_bool(engine.context, 1));
            return .{ .complete = c.JS_DupValue(engine.context, value) };
        },
        .thrown => {
            if (try equal(&scope, mode, "catch")) {
                try scope.put(owner, "mode", try scope.text("yield"));
                return .{ .yielded = c.JS_DupValue(engine.context, value) };
            }
            try scope.put(owner, "closed", c.pi_js_bool(engine.context, 1));
            return .{ .thrown = c.JS_DupValue(engine.context, value) };
        },
    }
}
fn make(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return makeBody(engine, if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| sdk.fail(engine, err);
}
fn makeBody(engine: *em.Engine, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.object();
    inline for (.{ "mode", "input", "final" }, 0..) |key, index| try scope.put(owner, key, if (args.len > index) args[index] else c.pi_js_undefined());
    try scope.put(owner, "calls", if (args.len > 3) args[3] else try scope.array());
    try scope.put(owner, "closed", c.pi_js_bool(engine.context, 0));
    return gen.create(engine, owner, advance, c.pi_js_undefined());
}
fn install(engine: *em.Engine) !void {
    try engine.bindFunction("makeNativeGenerator", make, 4);
}
fn run(engine: *em.Engine, code: []const u8, filename: [:0]const u8) !void {
    const result = engine.evalModule(code, filename) catch |err| {
        std.debug.print("native generator: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}
test "native async generator functional real intrinsic brand prototype raw yield and explicit await" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    try run(engine,
        \\const root={},final={},calls=[],native=makeNativeGenerator('yield',root,Promise.resolve(final),calls),real=(async function*(){yield root;return final})();const proto=Object.getPrototypeOf(Object.getPrototypeOf(real));if(Object.getPrototypeOf(native)!==proto||Object.prototype.toString.call(native)!=='[object AsyncGenerator]'||native[Symbol.asyncIterator]()!==native)throw Error('actual intrinsic brand/prototype');const first=await proto.next.call(native,'ignored');if(first.done||first.value!==root)throw Error('raw yield identity');const last=await proto.next.call(native);if(!last.done||last.value!==final)throw Error('return Await');const awaited=makeNativeGenerator('await',Promise.resolve(root),final);if((await awaited.next()).value!==root||(await awaited.next()).value!==final)throw Error('body await');export const done=true;
    , "native-generator-brand.mjs");
}
test "native async generator functional queued next return throw retain ownership and assimilate thenables" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    try run(engine,
        \\const root={},final={},reason={},calls=[];let release;const deferred=new Promise(resolve=>release=resolve),iterator=makeNativeGenerator('yield',deferred,final,calls),first=iterator.next(),second=iterator.next();let early=false;first.then(()=>early=true);await Promise.resolve();if(early)throw Error('yield thenable not awaited');release(root);const a=await first,b=await second;if(a.value!==root||a.done||b.value!==final||!b.done)throw Error('serialized next requests');
        \\let open;const waiting=makeNativeGenerator('yield',new Promise(resolve=>open=resolve),final),active=waiting.next(),returned=waiting.return({then(resolve){resolve(final)}});let closedEarly=false;returned.then(()=>closedEarly=true);await Promise.resolve();if(closedEarly)throw Error('return bypassed active yield');open(root);if((await active).value!==root)throw Error('active value lost');const r=await returned;if(!r.done||r.value!==final)throw Error('return input thenable');
        \\let unblock;const completed=makeNativeGenerator('yield',root,final),completion=completed.return(new Promise(resolve=>unblock=resolve)),q1=completed.next(),q2=completed.next(),q3=completed.throw(reason).then(()=>{throw Error('throw unexpectedly resolved')},error=>error);unblock(root);const out=await Promise.all([completion,q1,q2,q3]);if(out[0].value!==root||!out[0].done||!out[1].done||!out[2].done||out[3]!==reason)throw Error('drain after awaiting completed return');export const done=true;
    , "native-generator-queue.mjs");
}
test "native async generator functional rejection getters start return and abrupt close preserve raw errors" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    try run(engine,
        \\const reason={},calls=[],root={},before=makeNativeGenerator('yield',root,root,calls);if((await before.return(root)).value!==root||calls.length!==0)throw Error('return entered suspended start');const thrown=makeNativeGenerator('yield',root,root,calls);let seen;try{await thrown.throw(reason)}catch(error){seen=error}if(seen!==reason||calls.length!==0)throw Error('throw entered suspended start');
        \\const poison={get then(){throw reason}},catching=makeNativeGenerator('catch',poison,root);if((await catching.next()).value!==reason)throw Error('yield rejection not injected at suspension');const failing=makeNativeGenerator('yield',poison,root);try{await failing.next()}catch(error){seen=error}if(seen!==reason||!(await failing.next()).done)throw Error('rejected yield not completed');
        \\const promise=Promise.resolve(root);Object.defineProperty(promise,'constructor',{get(){throw reason}});const awaited=makeNativeGenerator('await',promise,root);try{await awaited.next()}catch(error){seen=error}if(seen!==reason)throw Error('raw poisoned constructor');const closing=makeNativeGenerator('yield',root,root);await closing.next();try{await closing.throw(reason)}catch(error){seen=error}if(seen!==reason||!(await closing.next()).done)throw Error('abrupt close');let invalid;try{await Object.getPrototypeOf(closing).next.call({})}catch(error){invalid=error}if(!(invalid instanceof TypeError))throw Error('real brand guard');export const done=true;
    , "native-generator-rejections.mjs");
}
test "native async generator functional pending owner survives GC" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    try run(engine,
        \\globalThis.generatorRoot={};globalThis.generatorFinal={};let release;const pending=new Promise(resolve=>release=resolve);globalThis.nativeHeld=makeNativeGenerator('yield',pending,generatorFinal);globalThis.nativeNext=nativeHeld.next();globalThis.releaseNative=release;export const ready=true;
    , "native-generator-gc-prepare.mjs");
    c.JS_RunGC(engine.runtime);
    try run(engine, "releaseNative(generatorRoot);if((await nativeNext).value!==generatorRoot||(await nativeHeld.next()).value!==generatorFinal)throw Error('GC lost native owner');delete globalThis.nativeHeld;delete globalThis.nativeNext;delete globalThis.releaseNative;export const done=true;", "native-generator-gc-check.mjs");
    c.JS_RunGC(engine.runtime);
}
test "native async generator host GPA allocation sweep retains tagged OOM" {
    const Probe = struct {
        fn check(gpa: std.mem.Allocator) !void {
            const subject = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer subject.deinit();
            const generation = subject.native_allocation_generation;
            install(subject) catch |err| return subject.nativeAllocationError(err, generation);
            run(subject, "const root={},it=makeNativeGenerator('yield',root,root);if((await it.next()).value!==root||(await it.next()).value!==root)throw Error('native generator allocations');export const done=true;", "native-generator-host-oom.mjs") catch |err| return subject.nativeAllocationError(err, generation);
            c.JS_RunGC(subject.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.check, .{});
}
test "native async generator functional cross realm callback and iterator result ownership" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const other = c.JS_NewContext(engine.runtime) orelse return error.OutOfMemory;
    defer c.JS_FreeContext(other);
    const args = [_]c.JSValue{ try sdk.text(engine, "yield"), try sdk.object(engine), c.pi_js_undefined() };
    defer for (args) |value| engine.freeValue(value);
    const native = try makeBody(engine, &args);
    defer engine.freeValue(native);
    const foreign_proto = try engine.checked(c.JS_PiGetAsyncGeneratorPrototype(other));
    defer engine.freeValue(foreign_proto);
    const foreign_next = try engine.checked(c.JS_GetPropertyStr(other, foreign_proto, "next"));
    defer engine.freeValue(foreign_next);
    const promise = try engine.checked(c.JS_Call(other, foreign_next, native, 0, null));
    defer engine.freeValue(promise);
    const global_b = c.JS_GetGlobalObject(other);
    defer engine.freeValue(global_b);
    const promise_b = try engine.checked(c.JS_GetPropertyStr(other, global_b, "Promise"));
    defer engine.freeValue(promise_b);
    const promise_proto_b = try engine.checked(c.JS_GetPropertyStr(other, promise_b, "prototype"));
    defer engine.freeValue(promise_proto_b);
    const actual_promise_proto = try engine.checked(c.JS_GetPrototype(other, promise));
    defer engine.freeValue(actual_promise_proto);
    try std.testing.expect(c.JS_IsStrictEqual(other, actual_promise_proto, promise_proto_b));
    const first = try engine.awaitValue(promise);
    defer engine.freeValue(first);
    const first_value = try js.get(engine, first, "value");
    defer engine.freeValue(first_value);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first_value, args[1]));
    const global_a = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global_a);
    const object_a = try js.get(engine, global_a, "Object");
    defer engine.freeValue(object_a);
    const object_proto_a = try js.get(engine, object_a, "prototype");
    defer engine.freeValue(object_proto_a);
    const result_proto = try engine.checked(c.JS_GetPrototype(engine.context, first));
    defer engine.freeValue(result_proto);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, result_proto, object_proto_a));
    const returned_promise = try engine.checked(c.JS_Call(other, foreign_next, native, 0, null));
    defer engine.freeValue(returned_promise);
    const returned = try engine.awaitValue(returned_promise);
    defer engine.freeValue(returned);
    const completed_promise = try engine.checked(c.JS_Call(other, foreign_next, native, 0, null));
    defer engine.freeValue(completed_promise);
    const completed = try engine.awaitValue(completed_promise);
    defer engine.freeValue(completed);
    const object_b = try engine.checked(c.JS_GetPropertyStr(other, global_b, "Object"));
    defer engine.freeValue(object_b);
    const object_proto_b = try engine.checked(c.JS_GetPropertyStr(other, object_b, "prototype"));
    defer engine.freeValue(object_proto_b);
    const completed_proto = try engine.checked(c.JS_GetPrototype(other, completed));
    defer engine.freeValue(completed_proto);
    try std.testing.expect(c.JS_IsStrictEqual(other, completed_proto, object_proto_b));
}
test "native async generator functional raw VM allocation failures reject and retire without dangling frame" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    c.JS_SetDumpFlags(engine.runtime, c.JS_DUMP_LEAKS);
    const root = try sdk.object(engine);
    defer engine.freeValue(root);
    const saved_limit = engine.options.memory_limit;
    c.JS_SetMemoryLimit(engine.runtime, 0);
    const failed_constructor = c.JS_PiNewNativeAsyncGenerator(engine.context, root, completeBody, c.pi_js_undefined());
    const constructor_exception = c.JS_GetException(engine.context);
    c.JS_SetMemoryLimit(engine.runtime, saved_limit);
    defer engine.freeValue(constructor_exception);
    try std.testing.expect(c.JS_IsException(failed_constructor));
    try std.testing.expect(!c.JS_IsUndefined(constructor_exception));
    const mode = try sdk.text(engine, "vm-oom");
    defer engine.freeValue(mode);
    const native = try makeBody(engine, &.{ mode, root });
    defer engine.freeValue(native);
    const next = try js.get(engine, native, "next");
    defer engine.freeValue(next);
    const promise = c.JS_Call(engine.context, next, native, 0, null);
    c.JS_SetMemoryLimit(engine.runtime, saved_limit);
    defer engine.freeValue(promise);
    try std.testing.expect(!c.JS_IsException(promise));
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, promise));
    const raw = c.JS_PromiseResult(engine.context, promise);
    defer engine.freeValue(raw);
    try std.testing.expect(!c.JS_IsUndefined(raw));
    try std.testing.expect(!c.JS_HasException(engine.context));
    const later = try js.invoke(engine, native, "next", &.{});
    defer engine.freeValue(later);
    const terminal = try engine.awaitValue(later);
    defer engine.freeValue(terminal);
    const done = try js.get(engine, terminal, "done");
    defer engine.freeValue(done);
    try std.testing.expect(c.JS_ToBool(engine.context, done) == 1);
    c.JS_RunGC(engine.runtime);
}
test "native async generator functional owner retirement and unreachable owner cycles finalize exactly once" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var retired: usize = 0;
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const Owner = struct {
        fn finalize(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
            const counter: *usize = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
            counter.* += 1;
        }
    };
    const definition: c.JSClassDef = .{ .class_name = "Native Generator Test Owner", .finalizer = Owner.finalize };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const owner = try engine.checked(c.JS_NewObjectClass(engine.context, @intCast(class)));
    _ = c.JS_SetOpaque(owner, &retired);
    const native = try engine.checked(c.JS_PiNewNativeAsyncGenerator(engine.context, owner, completeBody, c.pi_js_undefined()));
    engine.freeValue(owner);
    c.JS_RunGC(engine.runtime);
    try std.testing.expectEqual(@as(usize, 0), retired);
    const pending = try js.invoke(engine, native, "next", &.{});
    defer engine.freeValue(pending);
    const result = try engine.awaitValue(pending);
    defer engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
    try std.testing.expectEqual(@as(usize, 1), retired);
    engine.freeValue(native);
    const cyclic_owner = try engine.checked(c.JS_NewObjectClass(engine.context, @intCast(class)));
    _ = c.JS_SetOpaque(cyclic_owner, &retired);
    const cyclic_native = try engine.checked(c.JS_PiNewNativeAsyncGenerator(engine.context, cyclic_owner, completeBody, c.pi_js_undefined()));
    if (c.JS_DefinePropertyValueStr(engine.context, cyclic_owner, "iterator", c.JS_DupValue(engine.context, cyclic_native), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    engine.freeValue(cyclic_native);
    engine.freeValue(cyclic_owner);
    c.JS_RunGC(engine.runtime);
    try std.testing.expectEqual(@as(usize, 2), retired);
    c.JS_RunGC(engine.runtime);
    try std.testing.expectEqual(@as(usize, 2), retired);
}
comptime {
    _ = @import("native_ai_json_parse_test.zig");
    _ = @import("native_models_stream_regression_test.zig");
}

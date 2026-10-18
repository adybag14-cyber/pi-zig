//! UNRUN causal ownership controls. These native finalizers are test producers,
//! not substitutes for the product Chalk implementation or Source observations.
const std = @import("std");
const em = @import("engine.zig");
const chalk = @import("native_sdk_chalk.zig");
const owned = @import("native_sdk_owned_completion.zig");
const c = em.c;
const Probe = struct { engine: *em.Engine, count: *usize, reason: c.JSValue, symbol: c.JSValue };
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    state.count.* += 1;
    _ = c.JS_Throw(state.engine.context, state.reason); // Consume own B once.
    c.JS_FreeValueRT(runtime, state.symbol);
    state.engine.gpa.destroy(state);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, state.reason, marker); c.JS_MarkValue(runtime, state.symbol, marker);
}
fn call(context: ?*c.JSContext, value: c.JSValue, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int) callconv(.c) c.JSValue {
    const state: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
    return c.JS_Call(context, state.symbol, c.pi_js_undefined(), argc, argv);
}
fn probe(engine: *em.Engine, count: *usize, reason: c.JSValue, symbol: c.JSValue) !c.JSValue {
    var class: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "ChalkCleanupWitness", .finalizer = finalize, .gc_mark = mark, .call = call };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const state = try engine.gpa.create(Probe); errdefer engine.gpa.destroy(state);
    const value = try engine.checked(c.JS_NewObjectProtoClass(engine.context, c.pi_js_null(), class));
    state.* = .{ .engine = engine, .count = count, .reason = c.JS_DupValue(engine.context, reason), .symbol = c.JS_DupValue(engine.context, symbol) };
    _ = c.JS_SetOpaque(value, state); return value;
}
fn global(engine: *em.Engine, name: [*:0]const u8, value: c.JSValue) !void {
    const root = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(root);
    if (c.JS_DefinePropertyValueStr(engine.context, root, name, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
}
fn getGlobal(engine: *em.Engine, name: [*:0]const u8) !c.JSValue {
    const root = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(root);
    return engine.checked(c.JS_GetPropertyStr(engine.context, root, name));
}
fn take(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const root = c.JS_GetGlobalObject(context); defer c.JS_FreeValue(context, root);
    const result = c.JS_GetPropertyStr(context, root, "cleanupSeed");
    const atom = c.JS_NewAtom(context, "cleanupSeed"); defer c.JS_FreeAtom(context, atom);
    _ = c.JS_DeleteProperty(context, root, atom, 0); return result;
}
fn rawOOM(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const value = take(context, receiver, argc, argv);
    _ = em.Engine.fromContext(context.?).throwNativeOutOfMemoryFatal();
    return value; // Deliberately live result PLUS actual fresh pending OOM.
}
fn reenter(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return chalk.createDefault(engine) catch |err| @import("native_sdk.zig").fail(engine, err);
}
fn platform(engine: *em.Engine) !void {
    var env: std.process.Environ.Map = .init(std.testing.allocator); defer env.deinit(); try env.put("FORCE_COLOR", "0");
    try @import("native_process.zig").install(engine, std.testing.io, &env, &.{"private-chalk-ownership"});
    try @import("native_node_os.zig").install(engine);
}
fn eval(engine: *em.Engine, source: []const u8) !void { const result = try engine.eval(source, "chalk-owned-control.js", c.JS_EVAL_TYPE_GLOBAL); engine.freeValue(result); }
test "private consumed Chalk6 first ordinary raw A survives native cleanup B and historical DATA stays catchable" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try platform(engine);
    try global(engine, "privateChalk", try chalk.createDefault(engine));
    try eval(engine, "globalThis.ordinaryA={a:1};globalThis.cleanupB={b:1}");
    const reason = try getGlobal(engine, "cleanupB"); defer engine.freeValue(reason); var count: usize = 0;
    try global(engine, "cleanupSeed", try probe(engine, &count, reason, c.pi_js_undefined()));
    try global(engine, "takeCleanupProbe", try engine.checked(c.JS_NewCFunction(engine.context, take, "takeCleanupProbe", 0)));
    try eval(engine, "let reads=0,caught=false;try{privateChalk.constructor({get level(){if(++reads===1)return takeCleanupProbe();throw ordinaryA}})}catch(error){caught=error===ordinaryA}if(!caught||reads!==2)throw Error('first ordinary A displaced')");
    try std.testing.expectEqual(@as(usize, 1), count);
    _ = engine.throwNativeOutOfMemory(); const historical = c.JS_GetException(engine.context);
    try std.testing.expect(!c.JS_IsUncatchableError(historical)); try global(engine, "historicalChalkReason", historical);
    try eval(engine, "let historicalCaught=false;try{privateChalk.constructor({get level(){throw historicalChalkReason}})}catch(error){historicalCaught=error===historicalChalkReason}if(!historicalCaught)throw Error('old private tag promoted')");
}
test "private consumed Chalk6 fresh raw pending OOM and direct GPA failure survive owned cleanup" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try platform(engine);
    try global(engine, "privateChalk", try chalk.createDefault(engine)); try eval(engine, "globalThis.cleanupB={b:1}");
    const reason = try getGlobal(engine, "cleanupB"); defer engine.freeValue(reason); var count: usize = 0;
    try global(engine, "cleanupSeed", try probe(engine, &count, reason, c.pi_js_undefined()));
    const number = try getGlobal(engine, "Number"); defer engine.freeValue(number);
    const safe = try engine.checked(c.JS_GetPropertyStr(engine.context, number, "isSafeInteger")); defer engine.freeValue(safe);
    if (c.JS_SetPropertyStr(engine.context, number, "isSafeInteger", try engine.checked(c.JS_NewCFunction(engine.context, rawOOM, "rawChalkOOM", 1))) < 0) return error.JavaScriptException;
    const invoke = try engine.eval("(()=>privateChalk.constructor({level:1}))", "chalk-raw-oom.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(invoke);
    const result = c.JS_Call(engine.context, invoke, c.pi_js_undefined(), 0, null);
    try std.testing.expect(c.JS_IsException(result)); const actual = c.JS_GetException(engine.context); defer engine.freeValue(actual);
    try std.testing.expect(c.JS_IsUncatchableError(actual)); try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, engine.native_allocation_exception.?));
    try std.testing.expectEqual(@as(usize, 1), count);
    if (c.JS_SetPropertyStr(engine.context, number, "isSafeInteger", c.JS_DupValue(engine.context, safe)) < 0) return error.JavaScriptException;
    const temporary = try probe(engine, &count, reason, c.pi_js_undefined());
    var s: @import("native_sdk_chalk_scope.zig").Scope = .{ .engine = engine };
    for (&s.inline_values) |*slot| slot.* = c.pi_js_undefined(); s.inline_count = s.inline_values.len;
    var failure = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    const original_allocator = engine.gpa; engine.gpa = failure.allocator();
    const tracked = s.own(temporary); engine.gpa = original_allocator;
    const finished = owned.finishValue(&s, tracked);
    if (finished) |unexpected| { engine.freeValue(unexpected); return error.ExpectedChalkGpaFailure; } else |err| try std.testing.expect(err == error.JavaScriptException);
    try std.testing.expect(c.JS_IsUncatchableError(engine.captured_exception.?)); try std.testing.expectEqual(@as(usize, 2), count);
}
test "private consumed Chalk6 initializer reentry rejection and failed cleanup never publish cache" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try platform(engine);
    try global(engine, "reenterChalk", try engine.checked(c.JS_NewCFunction(engine.context, reenter, "reenterChalk", 0)));
    try eval(engine, "globalThis.savedSymbol=Symbol;globalThis.reentries=[];globalThis.Symbol=function(...args){try{reenterChalk();reentries.push(false)}catch(error){reentries.push(error instanceof TypeError)}return savedSymbol(...args)}");
    const value = try chalk.createDefault(engine); defer engine.freeValue(value);
    try eval(engine, "globalThis.Symbol=savedSymbol;if(reentries.length!==4||reentries.some(value=>!value))throw Error('initializer reentry guard')");
    const again = try chalk.createDefault(engine); defer engine.freeValue(again); try std.testing.expect(c.JS_IsStrictEqual(engine.context, value, again));
    // A fresh Engine proves cache publication follows successful retirement.
    const fresh = try em.Engine.init(std.testing.allocator, .{}); defer fresh.deinit(); try platform(fresh);
    try eval(fresh, "globalThis.savedSymbol=Symbol;globalThis.cleanupB={b:1};globalThis.symbolReads=0");
    const symbol = try getGlobal(fresh, "savedSymbol"); defer fresh.freeValue(symbol); const reason = try getGlobal(fresh, "cleanupB"); defer fresh.freeValue(reason); var count: usize = 0;
    try global(fresh, "cleanupSeed", try probe(fresh, &count, reason, symbol));
    try global(fresh, "takeCleanupProbe", try fresh.checked(c.JS_NewCFunction(fresh.context, take, "takeCleanupProbe", 0)));
    try eval(fresh, "Object.defineProperty(globalThis,'Symbol',{configurable:true,get(){if(++symbolReads===4)return takeCleanupProbe();return cleanupSeed}})");
    if (chalk.createDefault(fresh)) |unexpected| { fresh.freeValue(unexpected); return error.ExpectedChalkCleanupFailure; } else |err| try std.testing.expect(err == error.JavaScriptException);
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expect(c.JS_IsStrictEqual(fresh.context, fresh.captured_exception.?, reason));
    try std.testing.expect(!fresh.native_module_values.contains("\x00sdk-actual-chalk6-consumed-default"));
    try std.testing.expect(!fresh.native_module_values.contains("\x00sdk-actual-chalk6-initializing"));
}

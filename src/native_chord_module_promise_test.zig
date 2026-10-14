const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const latest = @import("native_chord_latest_source_test.zig");
const fulfilled =
    \\const descriptor=Object.getOwnPropertyDescriptor(Promise,Symbol.species),poison={species:true},native=Promise.resolve(41);let species=0,ownThen=0;Object.defineProperty(native,'then',{get(){ownThen++;throw poison}});Object.defineProperty(Promise,Symbol.species,{configurable:true,get(){species++;throw poison}});try{if(await native!==41)throw Error('native await');if(await{then(resolve){resolve(7)}}!==7)throw Error('thenable await');if(species||ownThen)throw Error('internal promise observation');let same=false;try{Promise.resolve(1).then(()=>{})}catch(e){same=e===poison}if(!same||species!==1)throw Error('public then species changed')}finally{Object.defineProperty(Promise,Symbol.species,descriptor)}export const answer=42;
;
const rejected =
    \\globalThis.moduleFailureMarker={original:true};const descriptor=Object.getOwnPropertyDescriptor(Promise,Symbol.species);Object.defineProperty(Promise,Symbol.species,{configurable:true,get(){throw Error('module must not observe species')}});try{await Promise.resolve();throw moduleFailureMarker}finally{Object.defineProperty(Promise,Symbol.species,descriptor)}
;
const dynamic =
    \\globalThis.dynamicFailureMarker={dynamic:true};const descriptor=Object.getOwnPropertyDescriptor(Promise,Symbol.species),poison={species:true};let species=0,ownThen=0;Object.defineProperty(Promise,Symbol.species,{configurable:true,get(){species++;throw poison}});try{const loading=import('native-spec-success.mjs');Object.defineProperty(loading,'then',{get(){ownThen++;throw poison}});if((await loading).value!==7)throw Error('dynamic result');let same=false;try{await import('native-spec-rejection.mjs')}catch(e){same=e===dynamicFailureMarker}if(!same||species||ownThen)throw Error('dynamic rejection or internal observation')}finally{Object.defineProperty(Promise,Symbol.species,descriptor)}
;
fn create(gpa: std.mem.Allocator) !*em.Engine {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    engine.native_io = std.testing.io;
    return engine;
}
fn evaluate(engine: *em.Engine, source: []const u8, name: [:0]const u8) !void {
    const generation = engine.native_allocation_generation;
    const result = engine.evalModule(source, name) catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
}
fn rejectedIdentity(engine: *em.Engine) !void {
    const generation = engine.native_allocation_generation;
    if (engine.evalModule(rejected, "intrinsic-module-rejected.mjs")) |result| {
        engine.freeValue(result);
        return error.ExpectedModuleRejection;
    } else |err| {
        const mapped = engine.nativeAllocationError(err, generation);
        if (mapped != error.JavaScriptException) return mapped;
    }
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const marker = try engine.checked(c.JS_GetPropertyStr(engine.context, root, "moduleFailureMarker"));
    defer engine.freeValue(marker);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, marker, engine.captured_exception.?));
    try std.testing.expectEqual(@as(u64, 0), c.pi_js_native_allocation_error_generation(engine.captured_exception.?));
    engine.beginInvocation();
}
fn dynamicImports(engine: *em.Engine) !void {
    try engine.registerModule("native-spec-success.mjs", "await Promise.resolve();export const value=7;");
    try engine.registerModule("native-spec-rejection.mjs", "await Promise.resolve();throw globalThis.dynamicFailureMarker;");
    try evaluate(engine, dynamic, "intrinsic-module-dynamic.mjs");
}
fn armVmBudget(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var budget: u32 = undefined;
    if (argc != 1 or c.JS_ToUint32(context, &budget, argv[0]) < 0) return c.JS_ThrowTypeError(context, "VM budget argument required");
    var usage: c.JSMemoryUsage = undefined;
    c.JS_ComputeMemoryUsage(engine.runtime, &usage);
    c.JS_SetMemoryLimit(engine.runtime, @as(usize, @intCast(usage.malloc_size)) + budget + 1);
    return c.pi_js_undefined();
}
test "native Chord intrinsic module compiled inventory" {
    try latest.inventory("CHORD_MODULE_PROMISE_COMPILED_INVENTORY");
}
test "native Chord intrinsic module pure guest TLA ignores species and own then while public then retains species" {
    const engine = try create(std.testing.allocator);
    defer engine.deinit();
    try evaluate(engine, fulfilled, "intrinsic-module-fulfilled.mjs");
    c.JS_RunGC(engine.runtime);
}
test "native Chord intrinsic module pure guest rejected TLA preserves exact ordinary rejection identity" {
    const engine = try create(std.testing.allocator);
    defer engine.deinit();
    try rejectedIdentity(engine);
    c.JS_RunGC(engine.runtime);
}
test "native Chord intrinsic module pure guest dynamic import fulfillment rejection and own then ignore species" {
    const engine = try create(std.testing.allocator);
    defer engine.deinit();
    try dynamicImports(engine);
    c.JS_RunGC(engine.runtime);
}
test "native Chord intrinsic module complete pure guest TLA dynamic import identities and native GC allocation sweep" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
            defer if (failing.fail_index == std.math.maxInt(usize)) {
                std.debug.print("CHORD_MODULE_PROMISE_GPA_BASELINE_ALLOCATIONS={d}\n", .{failing.alloc_index});
            };
            const engine = try create(gpa);
            defer engine.deinit();
            defer c.JS_RunGC(engine.runtime);
            try evaluate(engine, fulfilled, "intrinsic-module-fulfilled.mjs");
            try rejectedIdentity(engine);
            try dynamicImports(engine);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
test "native Chord intrinsic module direct VM heap limit sweep settles TLA and dynamic import failures and releases memory owners" {
    const counts = c.pi_js_native_memory_owners();
    var failures: usize = 0;
    var successes: usize = 0;
    var failures_by_program: [2]usize = .{ 0, 0 };
    var successes_by_program: [2]usize = .{ 0, 0 };
    var completed: usize = 0;
    for (0..2) |program| {
        for (0..257) |step| {
            const budget = step * 32;
            var unexpected: ?anyerror = null;
            {
                const engine = try create(std.testing.allocator);
                defer engine.deinit();
                defer c.JS_RunGC(engine.runtime);
                defer c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
                try engine.bindFunction("nativeArmVmBudget", armVmBudget, 1);
                if (program == 1) try engine.registerModule("native-limit-import.mjs", "await 0;export const value=7;");
                const source = if (program == 0) try std.fmt.allocPrint(std.testing.allocator, "nativeArmVmBudget({d});await 0;export const value=7;", .{budget}) else try std.fmt.allocPrint(std.testing.allocator, "nativeArmVmBudget({d});const ns=await import('native-limit-import.mjs');if(ns.value!==7)throw Error('import value');export const value=ns.value;", .{budget});
                defer std.testing.allocator.free(source);
                if (engine.evalModule(source, "intrinsic-module-limit.mjs")) |result| {
                    defer engine.freeValue(result);
                    c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
                    const value = try engine.checked(c.JS_GetPropertyStr(engine.context, result, "value"));
                    defer engine.freeValue(value);
                    try std.testing.expect(c.JS_IsNumber(value));
                    var number: i32 = undefined;
                    if (c.JS_ToInt32(engine.context, &number, value) < 0) return error.ModuleResultConversionFailed;
                    try std.testing.expectEqual(@as(i32, 7), number);
                    successes += 1;
                    successes_by_program[program] += 1;
                } else |err| {
                    if (err == error.JavaScriptException) {
                        failures += 1;
                        failures_by_program[program] += 1;
                    } else unexpected = err;
                }
            }
            try std.testing.expectEqual(counts, c.pi_js_native_memory_owners());
            if (unexpected) |err| {
                std.debug.print("Direct VM heap limit program{d} budget{d} unexpected {s}\n", .{ program, budget, @errorName(err) });
                return err;
            }
            completed += 1;
        }
        try std.testing.expect(failures_by_program[program] > 0 and successes_by_program[program] > 0);
    }
    try std.testing.expect(failures > 0 and successes > 0);
    std.debug.print("CHORD_MODULE_VM_HEAP_LIMIT_COVERAGE={{\"programs\":2,\"minimum_budget\":0,\"maximum_budget\":8192,\"step\":32,\"completed\":{d},\"failures\":{d},\"successes\":{d},\"failures_by_program\":[{d},{d}],\"successes_by_program\":[{d},{d}],\"owner_leaks\":0}}\n", .{ completed, failures, successes, failures_by_program[0], failures_by_program[1], successes_by_program[0], successes_by_program[1] });
}

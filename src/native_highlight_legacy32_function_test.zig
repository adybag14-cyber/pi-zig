//! Isolated actual Original CJS legacy32 differential. No production binding.
const std = @import("std");
const em = @import("extensions/engine.zig");
const inherit = @import("extensions/native_highlight_inherit.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
fn setup(engine: *em.Engine) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "inheritAPI", try scope.own(try inherit.createLegacyPrototype(engine)));
}
fn exercise(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    setup(engine) catch |err| return engine.nativeAllocationError(err, generation);
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-highlight-legacy32-b45.input.txt"), "highlight-legacy-original32.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    {
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const global = try scope.own(c.JS_GetGlobalObject(engine.context));
        const rows = try scope.get(global, "sdkHighlightInheritRows");
        const raw = try engine.stringify(rows);
        defer gpa.free(raw);
        const expected_bytes = @embedFile("extensions/fixtures/sdk-highlight-legacy32-b45.json");
        const expected = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, expected_bytes, expected_bytes.len, "highlight-legacy-original32.json")));
        const expected_raw = try engine.stringify(expected);
        defer gpa.free(expected_raw);
        if (!std.mem.eql(u8, raw, expected_raw)) {
            std.debug.print("Actual Original legacy20 mismatch:\n{s}\nExpected:\n{s}\n", .{ raw, expected_raw });
            return error.LegacyFunctionSourceMismatch;
        }
    }
    const released = engine.eval("globalThis.legacyWeak=new WeakRef(inheritAPI);delete globalThis.inheritAPI;delete globalThis.sdkHighlightInheritRows;", "highlight-legacy-release.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(released);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const collected = engine.eval("legacyWeak.deref()===undefined", "highlight-legacy-gc.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| return engine.nativeAllocationError(err, generation);
    defer engine.freeValue(collected);
    if (c.JS_ToBool(engine.context, collected) != 1) return error.LegacyFunctionOwnerRetained;
}
test "native legacy32 CJS function matches actual Original32 callers arguments poison descriptors freeze and GC" {
    try exercise(std.testing.allocator);
}
test "native legacy32 CJS function releases every full original probe allocation failure" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "highlight-legacy-function32", exercise, .{});
}
fn cancel(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    em.Engine.fromContext(context.?).cancelled.store(true, .release);
    return c.pi_js_undefined();
}
test "native legacy32 CJS function restores inactive frames after actual native enumeration cancellation" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try setup(engine);
    {
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const global = try scope.own(c.JS_GetGlobalObject(engine.context));
        try scope.put(global, "cancelLegacyProbe", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, cancel, "cancelLegacyProbe", 0))));
    }
    const result = engine.eval("inheritAPI({get a(){cancelLegacyProbe();return 1},b:2})", "highlight-legacy-cancel.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.cancelled.store(false, .release);
    try std.testing.expectError(error.JavaScriptException, result);
    const restored = try engine.eval("if(inheritAPI.arguments!==null||inheritAPI.caller!==null||inheritAPI({ok:1}).ok!==1)throw Error('legacy cancellation frame not restored');", "highlight-legacy-restored.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(restored);
}

// Additional source-only targeted C-VM heap pressure diagnostic.
// This is NOT an exhaustive C malloc failure sweep or trusted OOM classifier.
fn armLegacyVmBudget(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var budget: u32 = undefined;
    if (argc != 1 or c.JS_ToUint32(context, &budget, argv[0]) < 0) return c.JS_ThrowTypeError(context, "VM budget argument required");
    var usage: c.JSMemoryUsage = undefined;
    c.JS_ComputeMemoryUsage(engine.runtime, &usage);
    c.JS_SetMemoryLimit(engine.runtime, @as(usize, @intCast(usage.malloc_size)) + budget + 1);
    return c.pi_js_undefined();
}
fn disarmLegacyVmBudget(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
    return c.pi_js_undefined();
}
fn createLegacyVmProbe(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return inherit.createLegacyPrototype(engine) catch |err| @import("extensions/native_sdk.zig").fail(engine, err);
}
test "native legacy32 CJS function targeted C VM heap budgets preserve recovery frames and release every memory owner" {
    const owners = c.pi_js_native_memory_owners();
    var failures = [_]usize{ 0, 0 };
    var successes = [_]usize{ 0, 0 };
    var completed: usize = 0;
    for (0..2) |program| {
        for (0..257) |step| {
            const budget = step * 32;
            {
                const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
                defer engine.deinit();
                defer c.JS_RunGC(engine.runtime);
                defer c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
                try setup(engine);
                try engine.bindFunction("nativeArmVmBudget", armLegacyVmBudget, 1);
                try engine.bindFunction("nativeDisarmVmBudget", disarmLegacyVmBudget, 0);
                try engine.bindFunction("nativeCreateLegacyProbe", createLegacyVmProbe, 0);
                const source = if (program == 0)
                    try std.fmt.allocPrint(std.testing.allocator, "globalThis.vmInput={{get a(){{nativeArmVmBudget({d});try{{return inheritAPI.arguments}}finally{{nativeDisarmVmBudget()}}}}}};globalThis.vmValue=inheritAPI(vmInput);", .{budget})
                else
                    try std.fmt.allocPrint(std.testing.allocator, "nativeArmVmBudget({d});let fn;try{{fn=nativeCreateLegacyProbe()}}finally{{nativeDisarmVmBudget()}}globalThis.vmCreated=fn;", .{budget});
                defer std.testing.allocator.free(source);
                const outcome = engine.eval(source, "legacy-targeted-vm-budget.js", c.JS_EVAL_TYPE_GLOBAL);
                // Restore before inspecting, allocating, running GC or deinitializing.
                c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
                if (outcome) |result| {
                    engine.freeValue(result);
                    if (program == 1) {
                        // Validate outside the pressure outcome classifier, with
                        // the normal limit restored. A real invariant failure
                        // must fail this test rather than count as VM pressure.
                        const constructed = try engine.eval("if(vmCreated.name!=='inherit')throw Error('legacy constructor result');", "legacy-vm-constructor-recovery.js", c.JS_EVAL_TYPE_GLOBAL);
                        engine.freeValue(constructed);
                    }
                    successes[program] += 1;
                } else |err| {
                    // Ordinary JS_EXCEPTION under this explicitly armed limit is
                    // pressure evidence only; never relabel it trusted native OOM.
                    if (err != error.JavaScriptException) return err;
                    failures[program] += 1;
                }
                const recovered = try engine.eval("if(inheritAPI.arguments!==null||inheritAPI.caller!==null||inheritAPI({ok:1}).ok!==1)throw Error('legacy frame recovery under VM budget');", "legacy-vm-recovery.js", c.JS_EVAL_TYPE_GLOBAL);
                engine.freeValue(recovered);
                engine.finishJob();
            }
            try std.testing.expectEqual(owners, c.pi_js_native_memory_owners());
            completed += 1;
        }
        try std.testing.expect(failures[program] > 0 and successes[program] > 0);
    }
    std.debug.print("LEGACY_FUNCTION_VM_HEAP_LIMIT_COVERAGE={{\"programs\":2,\"minimum_budget\":0,\"maximum_budget\":8192,\"step\":32,\"completed\":{d},\"failures\":[{d},{d}],\"successes\":[{d},{d}],\"owner_leaks\":0,\"exhaustive_C_malloc\":false,\"trusted_OOM_classification\":false}}\n", .{ completed, failures[0], failures[1], successes[0], successes[1] });
}

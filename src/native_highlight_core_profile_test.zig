//! Separate allocation measurement; this never replaces the full GPA checker.
const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_highlight_scope.zig").Scope;
const c = em.c;
threadlocal var factory_allocator: ?*std.testing.FailingAllocator = null;
fn allocationFailureFactory(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const allocator = factory_allocator.?.allocator();
    const value = allocator.alloc(u8, 1) catch return engine.throwNativeOutOfMemory();
    allocator.free(value);
    return c.JS_ThrowInternalError(context, "Expected the factory host allocator to fail");
}
test "native highlight inline profile unchanged actual74 full body and allocation baseline measurement only" {
    var counter = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try @import("native_highlight_core_b45_test.zig").exercise(counter.allocator());
    try std.testing.expectEqual(counter.allocated_bytes, counter.freed_bytes);
    std.debug.print("HIGHLIGHT_INLINE_PROFILE actual_source_cases=74 eager_factories=21 baseline={d} allocated_bytes={d} freed_bytes={d} full_GPA=false\n", .{ counter.alloc_index, counter.allocated_bytes, counter.freed_bytes });
}
test "native highlight inline profile registration preserves proven host OOM and ordinary guest lookalikes" {
    const owners = c.pi_js_native_memory_owners();
    {
        const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
        defer engine.deinit();
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const loggers = try scope.own(try @import("extensions/native_highlight_loggers.zig").create(engine));
        const core = try scope.own(try @import("extensions/native_highlight_core.zig").create(engine, loggers));
        const global = try scope.own(c.JS_GetGlobalObject(engine.context));
        try scope.put(global, "registrationCore", core);
        try scope.put(global, "allocationFailureFactory", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, allocationFailureFactory, "allocationFailureFactory", 1))));
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
        factory_allocator = &failing;
        defer factory_allocator = null;
        const generation = engine.native_allocation_generation;
        const outcome = engine.eval("registrationCore.registerLanguage('host-allocation-failure',allocationFailureFactory)", "highlight-registration-host-oom.js", c.JS_EVAL_TYPE_GLOBAL);
        try std.testing.expectError(error.JavaScriptException, outcome);
        try std.testing.expectEqual(error.OutOfMemory, engine.nativeAllocationError(error.JavaScriptException, generation));
        try std.testing.expect(failing.has_induced_failure);
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        try std.testing.expectEqual(generation + 1, engine.native_allocation_generation);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, engine.captured_exception.?, engine.native_allocation_exception.?));
        const control = try engine.eval(
            \\globalThis.console={error(){}};
            \\const lookalike=new Error('out of memory');lookalike.name='OutOfMemory';
            \\registrationCore.registerLanguage('guest-lookalike',()=>{throw lookalike});
            \\if(!registrationCore.getLanguage('guest-lookalike'))throw Error('Ordinary Source registration fallback changed');
            \\if(registrationCore.getLanguage('host-allocation-failure')!==undefined)throw Error('Host OOM incorrectly registered plaintext');
            \\registrationCore.unregisterLanguage('guest-lookalike');delete globalThis.registrationCore;delete globalThis.allocationFailureFactory;
        , "highlight-registration-guest-oom-control.js", c.JS_EVAL_TYPE_GLOBAL);
        engine.freeValue(control);
        try std.testing.expectEqual(generation + 1, engine.native_allocation_generation);
        engine.finishJob();
        c.JS_RunGC(engine.runtime);
    }
    try std.testing.expectEqual(owners, c.pi_js_native_memory_owners());
}

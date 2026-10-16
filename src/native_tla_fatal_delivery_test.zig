const std = @import("std");
const em = @import("extensions/engine.zig");
const af = @import("extensions/native_async_function.zig");
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const AllocationScope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;

fn fatalStart(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return error.OutOfMemory;
}
fn installFatal(engine: *em.Engine) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "fatalStart", try scope.own(try af.create(engine, "fatalStart", 0, fatalStart, &.{})));
}
fn compile(engine: *em.Engine, source: []const u8, filename: [:0]const u8) !c.JSValue {
    return engine.eval(source, filename, c.JS_EVAL_TYPE_MODULE | c.JS_EVAL_FLAG_COMPILE_ONLY);
}
fn evaluate(engine: *em.Engine, module: c.JSValue) c.JSValue {
    return c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, module));
}
fn captureFatal(engine: *em.Engine, result: c.JSValue, boundary: u64) !void {
    defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsException(result));
    try std.testing.expectError(error.JavaScriptException, engine.checked(result));
    const reason = engine.captured_exception orelse return error.MissingFatalReason;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.native_allocation_exception.?));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(engine.nativeAllocationError(error.JavaScriptException, boundary) == error.OutOfMemory);
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
}
fn cachedFatal(engine: *em.Engine, module: c.JSValue) !void {
    const boundary = engine.native_allocation_generation;
    const expected = c.JS_DupValue(engine.context, engine.native_allocation_exception.?);
    defer engine.freeValue(expected);
    const result = evaluate(engine, module);
    defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsException(result));
    const reason = c.JS_GetException(engine.context);
    defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, expected, reason));
    // Host classification already cleared the bit. Cached module failure is
    // terminal bookkeeping, not a newly fabricated/retagged allocation error.
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(boundary, engine.native_allocation_generation);
    try std.testing.expectError(error.JavaScriptException, engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason))));
    try std.testing.expect(engine.nativeAllocationError(error.JavaScriptException, boundary) == error.JavaScriptException);
    try std.testing.expect(!c.JS_HasException(engine.context));
}

test "native TLA fatal immediate genuine START is delivered and cached without retagging" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try installFatal(engine);
    const module = try compile(engine, "await fatalStart();", "tla-fatal-immediate.mjs");
    defer engine.freeValue(module);
    const boundary = engine.native_allocation_generation;
    try captureFatal(engine, evaluate(engine, module), boundary);
    try cachedFatal(engine, module);
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    const healthy = try engine.evalModule("await Promise.resolve(); export const healthy=true;", "tla-healthy-after-fatal.mjs");
    engine.freeValue(healthy);
    try cachedFatal(engine, module);
    c.JS_RunGC(engine.runtime);
}

test "native TLA fatal Engine evalModule delivers fresh allocation error terminally" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try installFatal(engine);
    const boundary = engine.native_allocation_generation;
    try std.testing.expectError(error.JavaScriptException, engine.evalModule("await fatalStart();", "tla-engine-immediate.mjs"));
    try std.testing.expect(engine.nativeAllocationError(error.JavaScriptException, boundary) == error.OutOfMemory);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, engine.captured_exception.?, engine.native_allocation_exception.?));
}

fn deferredFatal(source: []const u8, filename: [:0]const u8) !void {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try installFatal(engine);
    try engine.registerModule("fatal-dependency", "await Promise.resolve(); export const ready=true;");
    try engine.registerModule("fatal-ancestor", source);
    // The failing ancestor has an additional waiting parent: terminal state
    // must propagate there too, rather than fixing only the failing module.
    const module = try compile(engine, "import 'fatal-ancestor'; export const parent=true;", filename);
    defer engine.freeValue(module);
    const boundary = engine.native_allocation_generation;
    const pending = evaluate(engine, module);
    defer engine.freeValue(pending);
    try std.testing.expect(!c.JS_IsException(pending));
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, pending));
    try std.testing.expectError(error.JavaScriptException, engine.awaitValue(pending));
    const reason = engine.captured_exception orelse return error.MissingFatalReason;
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.native_allocation_exception.?));
    try std.testing.expect(engine.nativeAllocationError(error.JavaScriptException, boundary) == error.OutOfMemory);
    try cachedFatal(engine, module);
    const importer = try compile(engine, "import 'fatal-ancestor'; export const unreachable=true;", "tla-import-cached-fatal.mjs");
    defer engine.freeValue(importer);
    const cached_boundary = engine.native_allocation_generation;
    const imported = evaluate(engine, importer);
    defer engine.freeValue(imported);
    try std.testing.expect(c.JS_IsException(imported));
    const imported_reason = c.JS_GetException(engine.context);
    defer engine.freeValue(imported_reason);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, imported_reason, engine.native_allocation_exception.?));
    try std.testing.expectEqual(cached_boundary, engine.native_allocation_generation);
    c.JS_RunGC(engine.runtime);
}
test "native TLA fatal deferred async ancestor START escapes the actual dependency job" {
    try deferredFatal("import 'fatal-dependency'; fatalStart(); await 0;", "tla-deferred-async-ancestor.mjs");
}
test "native TLA fatal deferred synchronous ancestor escapes the actual dependency job" {
    try deferredFatal("import 'fatal-dependency'; fatalStart(); export const unreachable=true;", "tla-deferred-sync-ancestor.mjs");
}

test "native TLA fatal ordinary raw lookalike and historical errors remain exact rejected promises" {
    const kinds = [_][]const u8{ "({raw:true})", "Object.assign(new Error('out of memory'),{name:'InternalError'})", "historicalNative" };
    for (kinds) |expression| {
        const engine = try em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try installFatal(engine);
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const global = try scope.own(c.JS_GetGlobalObject(engine.context));
        const fatal = try scope.get(global, "fatalStart");
        const born = engine.native_allocation_generation;
        try captureFatal(engine, c.JS_Call(engine.context, fatal, c.pi_js_undefined(), 0, null), born);
        try scope.put(global, "historicalNative", engine.native_allocation_exception.?);
        const source = try std.fmt.allocPrint(std.testing.allocator, "globalThis.tlaReason={s}; await Promise.reject(tlaReason);", .{expression});
        defer std.testing.allocator.free(source);
        const module = try compile(engine, source, "tla-ordinary-rejection.mjs");
        defer engine.freeValue(module);
        const boundary = engine.native_allocation_generation;
        const promise = evaluate(engine, module);
        defer engine.freeValue(promise);
        try std.testing.expect(!c.JS_IsException(promise));
        try std.testing.expectError(error.JavaScriptException, engine.awaitValue(promise));
        const reason = try scope.get(global, "tlaReason");
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.captured_exception.?));
        try std.testing.expect(!c.JS_IsUncatchableError(reason));
        try std.testing.expect(engine.nativeAllocationError(error.JavaScriptException, boundary) == error.JavaScriptException);
        const cached = evaluate(engine, module);
        defer engine.freeValue(cached);
        try std.testing.expect(!c.JS_IsException(cached));
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, promise, cached));
        try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, cached));
        const cached_reason = c.JS_PromiseResult(engine.context, cached);
        defer engine.freeValue(cached_reason);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, cached_reason));
        try std.testing.expect(!c.JS_HasException(engine.context));
    }
}

fn allocateOwned(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: AllocationScope = .{ .engine = engine };
    defer scope.deinit();
    // The actual failure may occur while Scope.own grows after JS_NewObject.
    // Scope owns/free behavior is exercised, not replaced by a test mock.
    return c.JS_DupValue(engine.context, try scope.object());
}
test "native TLA fatal injected Zig allocation cleanup reaches the real module boundary" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{});
            defer engine.deinit();
            const boundary = engine.native_allocation_generation;
            var scope: Scope = .{ .engine = engine };
            defer scope.deinit();
            const global = try scope.own(c.JS_GetGlobalObject(engine.context));
            const function = af.create(engine, "allocateOwned", 0, allocateOwned, &.{}) catch |err| return engine.nativeAllocationError(err, boundary);
            try scope.put(global, "allocateOwned", try scope.own(function));
            const result = engine.evalModule("await allocateOwned(); export const complete=true;", "tla-owned-allocation.mjs") catch |err| return engine.nativeAllocationError(err, boundary);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}

fn armAttachmentBudget(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, budget: c_int) callconv(.c) c.JSValue {
    var usage: c.JSMemoryUsage = undefined;
    c.JS_ComputeMemoryUsage(c.JS_GetRuntime(context), &usage);
    c.JS_SetMemoryLimit(c.JS_GetRuntime(context), @as(usize, @intCast(usage.malloc_size)) + @as(usize, @intCast(budget)) + 1);
    return c.pi_js_undefined();
}
test "native TLA fatal bounded C attachment pressure has terminal outcomes and reusable cleanup" {
    var failed: usize = 0;
    var succeeded: usize = 0;
    // The limit is armed at the end of a syntactically asynchronous module,
    // after its async invocation/capability setup. These quotas target its
    // completion/handler0/handler1/then allocations. Site-specific allocation
    // coverage must be recorded from an authorized run; this is not exhaustive.
    for (0..65) |step| {
        const engine = try em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        defer c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const global = try scope.own(c.JS_GetGlobalObject(engine.context));
        const arm = try scope.own(try engine.checked(c.JS_NewCFunctionMagic(engine.context, armAttachmentBudget, "armAttachmentBudget", 0, c.JS_CFUNC_generic_magic, @intCast(step * 128))));
        try scope.put(global, "armAttachmentBudget", arm);
        const module = try compile(engine, "if(false) await 0; armAttachmentBudget();", "tla-attachment-pressure.mjs");
        defer engine.freeValue(module);
        const promise = evaluate(engine, module);
        c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
        defer engine.freeValue(promise);
        if (c.JS_IsException(promise)) {
            failed += 1;
            const first = c.JS_GetException(engine.context);
            defer engine.freeValue(first);
            const cached = evaluate(engine, module);
            defer engine.freeValue(cached);
            if (c.JS_IsUncatchableError(first)) {
                try std.testing.expect(c.JS_IsException(cached));
                const again = c.JS_GetException(engine.context);
                defer engine.freeValue(again);
                try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, again));
            } else return error.CatchableAttachmentErrorEscapedPromise;
        } else settlement: {
            const settled = engine.awaitValue(promise) catch |err| {
                try std.testing.expect(err == error.JavaScriptException);
                failed += 1;
                const first = c.JS_DupValue(engine.context, engine.captured_exception.?);
                defer engine.freeValue(first);
                const cached = evaluate(engine, module);
                defer engine.freeValue(cached);
                try std.testing.expect(!c.JS_IsException(cached));
                try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, cached));
                const again = c.JS_PromiseResult(engine.context, cached);
                defer engine.freeValue(again);
                try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, again));
                break :settlement;
            };
            engine.freeValue(settled);
            succeeded += 1;
        }
        try std.testing.expect(!c.JS_HasException(engine.context));
        const healthy = try engine.evalModule("export const healthy=true;", "tla-after-pressure.mjs");
        engine.freeValue(healthy);
        c.JS_RunGC(engine.runtime);
    }
    try std.testing.expect(failed > 0);
    try std.testing.expect(succeeded > 0);
}

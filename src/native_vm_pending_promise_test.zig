//! Actual intrinsic pending Promise allocation and the original init-hook owner.
//! Source-only controls; no replacement resolver closures or guest constructor.
const std = @import("std");
const c = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("engine_abi.h");
});
const Fixture = struct {
    runtime: ?*c.JSRuntime = null,
    context: ?*c.JSContext = null,
    memory: ?*anyopaque = null,
    fn init(self: *Fixture) !void {
        self.* = .{};
        self.runtime = c.pi_js_new_runtime(64 * 1024 * 1024, &self.memory) orelse return error.OutOfMemory;
        errdefer self.deinit();
        self.context = c.JS_NewContext(self.runtime.?) orelse return error.OutOfMemory;
    }
    fn deinit(self: *Fixture) void {
        if (self.runtime) |runtime| {
            c.JS_SetPromiseHook(runtime, null, null);
            c.JS_SetMemoryLimit(runtime, 0);
            _ = c.JS_PiExchangeJavascriptExecutionAllowed(runtime, true);
        }
        if (self.context) |context| { self.context = null; c.JS_FreeContext(context); }
        if (self.runtime) |runtime| { self.runtime = null; c.JS_FreeRuntime(runtime); }
        if (self.memory) |memory| { self.memory = null; c.pi_js_release_memory_owner(memory); }
    }
    fn checked(self: *Fixture, value: c.JSValue) !c.JSValue {
        if (c.JS_IsException(value) or c.JS_HasException(self.context.?)) {
            if (!c.JS_IsException(value)) c.JS_FreeValue(self.context.?, value);
            if (c.JS_HasException(self.context.?)) {
                const reason = c.JS_GetException(self.context.?);
                c.JS_FreeValue(self.context.?, reason);
            }
            return error.ActualPendingPromiseControlException;
        }
        return value;
    }
    fn eval(self: *Fixture, source: [:0]const u8) !c.JSValue {
        return self.checked(c.JS_Eval(self.context.?, source.ptr, source.len,
            "actual-pending-promise.js", c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_STRICT));
    }
    fn run(self: *Fixture, source: [:0]const u8) !void {
        const result = try self.eval(source); defer c.JS_FreeValue(self.context.?, result);
    }
    fn set(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        const global_object = try self.checked(c.JS_GetGlobalObject(self.context.?));
        defer c.JS_FreeValue(self.context.?, global_object);
        try std.testing.expect(c.JS_SetPropertyStr(self.context.?, global_object, name,
            c.JS_DupValue(self.context.?, value)) >= 0);
        try std.testing.expect(!c.JS_HasException(self.context.?));
    }
    fn number(self: *Fixture, value: c.JSValue, expected: i32) !void {
        try std.testing.expect(c.JS_IsNumber(value));
        var actual: i32 = 0;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(self.context.?, &actual, value));
        try std.testing.expectEqual(expected, actual);
    }
    fn ownBool(self: *Fixture, record: c.JSValue, name: [*:0]const u8, expected: bool) !void {
        // The exact record and this primitive own data field predate the failure.
        const value = c.JS_GetPropertyStr(self.context.?, record, name);
        defer c.JS_FreeValue(self.context.?, value);
        try std.testing.expect(c.JS_IsBool(value));
        try std.testing.expectEqual(@as(c_int, @intFromBool(expected)), c.JS_ToBool(self.context.?, value));
    }
    fn pending(self: *Fixture) !c.JSValue {
        try std.testing.expect(c.JS_HasException(self.context.?));
        return c.JS_GetException(self.context.?);
    }
    fn objects(self: *Fixture) i64 {
        var usage: c.JSMemoryUsage = undefined;
        c.JS_ComputeMemoryUsage(self.runtime.?, &usage);
        return usage.obj_count;
    }
    fn drain(self: *Fixture) !usize {
        var count: usize = 0;
        while (c.JS_IsJobPending(self.runtime.?)) {
            if (count == 32) return error.ActualPendingPromiseJobBudget;
            var context: ?*c.JSContext = null;
            const status = c.JS_ExecutePendingJob(self.runtime.?, &context);
            try std.testing.expectEqual(@as(c_int, 1), status);
            try std.testing.expect(context == self.context.?);
            try std.testing.expect(!c.JS_HasException(self.context.?));
            count += 1;
        }
        return count;
    }
};
const Observation = struct {
    context: ?*c.JSContext = null,
    parent: c.JSValue,
    retained: c.JSValue,
    state: c.JSPromiseStateEnum = c.JS_PROMISE_NOT_A_PROMISE,
    objects: i64 = 0,
};
const Probe = struct {
    context: ?*c.JSContext = null,
    enabled: bool = false,
    class_id: c.JSClassID = 0,
    observations: [8]Observation = undefined,
    count: usize = 0,
    overflow: bool = false,
    retain_result: bool = false,
    nested: bool = false,
    nesting: bool = false,
    nested_failed: bool = false,
    nested_result: c.JSValue = undefined,
    callback: c.JSValue = undefined,
    marker: c.JSValue = undefined,
    settle_value: c.JSValue = undefined,
    settle_in_hook: bool = false,
    hook_reason: ?usize = null,
    cleanup_reason: ?usize = null,
    reasons: [2]c.JSValue = undefined,
    retirements: usize = 0,
    fn init(self: *Probe, f: *Fixture) !void {
        self.context = f.context.?;
        const nothing = c.pi_js_undefined();
        self.nested_result = nothing;
        self.callback = nothing;
        self.marker = nothing;
        self.settle_value = nothing;
        for (&self.reasons) |*reason_slot| reason_slot.* = nothing;
        for (&self.observations) |*item| item.* = .{ .parent = nothing, .retained = nothing };
        _ = c.JS_NewClassID(f.runtime.?, &self.class_id);
        const class_definition: c.JSClassDef = .{ .class_name = "Actual pending Promise marker", .finalizer = retire };
        try std.testing.expectEqual(@as(c_int, 0), c.JS_NewClass(f.runtime.?, self.class_id, &class_definition));
        self.enabled = true;
    }
    fn install(self: *Probe, f: *Fixture) void {
        c.JS_SetPromiseHook(f.runtime.?, hook, self);
    }
    fn disable(self: *Probe) void {
        self.enabled = false;
        const context = self.context orelse return;
        self.context = null;
        c.JS_SetPromiseHook(c.JS_GetRuntime(context), null, null);
        for (&self.observations) |*item| {
            const parent = item.parent; item.parent = c.pi_js_undefined();
            const retained = item.retained; item.retained = c.pi_js_undefined();
            c.JS_FreeValue(context, parent); c.JS_FreeValue(context, retained);
        }
        for ([_]*c.JSValue{ &self.nested_result, &self.callback, &self.marker, &self.settle_value }) |slot| {
            const value = slot.*; slot.* = c.pi_js_undefined(); c.JS_FreeValue(context, value);
        }
        for (&self.reasons) |*slot| {
            const value = slot.*; slot.* = c.pi_js_undefined(); c.JS_FreeValue(context, value);
        }
    }
    fn reason(self: *Probe, f: *Fixture, index: usize, fatal: bool) !void {
        self.reasons[index] = try f.checked(c.JS_NewError(f.context.?));
        if (fatal) c.JS_SetUncatchableError(f.context.?, self.reasons[index]);
    }
    fn makeMarker(self: *Probe, f: *Fixture) !void {
        const value = try f.checked(c.JS_NewObjectProtoClass(f.context.?, c.pi_js_null(), self.class_id));
        _ = c.JS_SetOpaque(value, self);
        self.marker = value;
    }
    fn retire(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
        const raw_owner = c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return;
        const self: *Probe = @ptrCast(@alignCast(raw_owner));
        _ = c.JS_SetOpaque(value, null);
        self.retirements += 1;
        if (!self.enabled) return;
        const context = self.context orelse return;
        if (self.cleanup_reason) |index| {
            self.cleanup_reason = null;
            _ = c.JS_Throw(context, c.JS_DupValue(context, self.reasons[index]));
        }
    }
    fn hook(context: ?*c.JSContext, kind: c.JSPromiseHookType, promise: c.JSValue,
        parent: c.JSValue, raw_owner: ?*anyopaque) callconv(.c) void
    {
        const ctx = context orelse return;
        const raw = raw_owner orelse return;
        const self: *Probe = @ptrCast(@alignCast(raw));
        if (!self.enabled or kind != c.JS_PROMISE_HOOK_INIT) return;
        if (self.count == self.observations.len) { self.overflow = true; return; }
        const index = self.count; self.count += 1;
        var usage: c.JSMemoryUsage = undefined;
        c.JS_ComputeMemoryUsage(c.JS_GetRuntime(ctx), &usage);
        self.observations[index] = .{
            .context = ctx,
            .parent = c.JS_DupValue(ctx, parent),
            .retained = if (self.retain_result) c.JS_DupValue(ctx, promise) else c.pi_js_undefined(),
            .state = c.JS_PromiseState(ctx, promise),
            .objects = usage.obj_count,
        };
        if (!c.JS_IsUndefined(self.marker)) {
            const marker = self.marker; self.marker = c.pi_js_undefined();
            if (c.JS_DefinePropertyValueStr(ctx, promise, "actualMarker", marker, c.JS_PROP_C_W_E) < 0) return;
        }
        if (self.nested and !self.nesting) {
            self.nesting = true;
            const nested_result = c.JS_PiNewPendingPromise(ctx);
            self.nesting = false;
            if (c.JS_IsException(nested_result)) { self.nested_failed = true; return; }
            self.nested_result = nested_result;
        }
        if (!c.JS_IsUndefined(self.callback)) {
            const args = [_]c.JSValue{ promise, parent };
            const result = c.JS_Call(ctx, self.callback, c.pi_js_undefined(), 2, @constCast(&args));
            if (!c.JS_IsException(result)) c.JS_FreeValue(ctx, result);
            if (c.JS_IsException(result) or c.JS_HasException(ctx)) return;
        }
        if (self.settle_in_hook) {
            const result = c.JS_PiSettlePromise(ctx, promise, self.settle_value, false);
            if (!c.JS_IsException(result)) c.JS_FreeValue(ctx, result);
            if (c.JS_IsException(result) or c.JS_HasException(ctx)) return;
        }
        if (self.hook_reason) |reason_index| {
            _ = c.JS_Throw(ctx, c.JS_DupValue(ctx, self.reasons[reason_index]));
        }
    }
    fn expectCount(self: *Probe, count: usize) !void {
        try std.testing.expect(!self.overflow);
        try std.testing.expectEqual(count, self.count);
        for (self.observations[0..count]) |item|
            try std.testing.expectEqual(c.JS_PROMISE_PENDING, item.state);
    }
};
fn allocateApi(context: ?*c.JSContext, _: c.JSValue, _: c_int,
    _: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue
{
    return c.JS_PiNewPendingPromise(context orelse return c.pi_js_exception());
}
fn installAllocator(f: *Fixture) !void {
    const callback = try f.checked(c.JS_NewCFunctionData2(f.context.?, allocateApi,
        "actualPendingPromise", 0, 0, 0, null));
    defer c.JS_FreeValue(f.context.?, callback);
    try std.testing.expectEqual(@as(c_int, 0), c.JS_PiMarkNativeApiFunction(f.context.?, callback));
    try f.set("allocate", callback);
}

test "VM pending Promise intrinsic allocation ignores the live global constructor and uses its actual realm prototype" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const prototype = try f.eval("Promise.prototype"); defer c.JS_FreeValue(f.context.?, prototype);
    try f.run("Object.defineProperty(globalThis,'Promise',{get(){throw Error('global Promise read');},configurable:true});");
    const promise = try f.checked(c.JS_PiNewPendingPromise(f.context.?));
    defer c.JS_FreeValue(f.context.?, promise);
    const actual_prototype = try f.checked(c.JS_GetPrototype(f.context.?, promise));
    defer c.JS_FreeValue(f.context.?, actual_prototype);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, prototype, actual_prototype));
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(f.context.?, promise));
    const result = c.JS_PromiseResult(f.context.?, promise); defer c.JS_FreeValue(f.context.?, result);
    try std.testing.expect(c.JS_IsUndefined(result));
    try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
}
test "VM pending Promise init sees one real object while the original resolving capability still creates its pair" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
    const baseline = f.objects();
    probe.install(&f);
    {
        const promise = try f.checked(c.JS_PiNewPendingPromise(f.context.?));
        defer c.JS_FreeValue(f.context.?, promise);
        try probe.expectCount(1);
        try std.testing.expectEqual(baseline + 1, probe.observations[0].objects);
        try std.testing.expectEqual(baseline + 1, f.objects());
        try std.testing.expect(c.JS_IsUndefined(probe.observations[0].parent));
    }
    try std.testing.expectEqual(baseline, f.objects());
    var resolving = [_]c.JSValue{ c.pi_js_undefined(), c.pi_js_undefined() };
    const original = try f.checked(c.JS_NewPromiseCapability(f.context.?, &resolving));
    defer c.JS_FreeValue(f.context.?, original);
    defer { for (resolving) |value| c.JS_FreeValue(f.context.?, value); }
    try probe.expectCount(2);
    try std.testing.expectEqual(baseline + 3, probe.observations[1].objects);
    try std.testing.expectEqual(baseline + 3, f.objects());
    try std.testing.expect(c.JS_IsFunction(f.context.?, resolving[0]));
    try std.testing.expect(c.JS_IsFunction(f.context.?, resolving[1]));
}
test "VM pending Promise direct init has undefined parent inside an actual parent-aware reaction allocation" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
    const parent = try f.checked(c.JS_PiNewPendingPromise(f.context.?));
    defer c.JS_FreeValue(f.context.?, parent);
    probe.nested = true; probe.install(&f);
    const child = try f.checked(c.JS_PromiseThen(f.context.?, parent, c.pi_js_undefined(), c.pi_js_undefined()));
    defer c.JS_FreeValue(f.context.?, child);
    try probe.expectCount(2);
    try std.testing.expect(!probe.nested_failed);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, parent, probe.observations[0].parent));
    try std.testing.expect(c.JS_IsUndefined(probe.observations[1].parent));
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(f.context.?, probe.nested_result));
    try std.testing.expect(!c.JS_IsStrictEqual(f.context.?, child, probe.nested_result));
    try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
}
test "VM pending Promise live init callback observes and modifies the exact object before return" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
    try f.run("globalThis.progress={seen:null,parent:9,calls:0};");
    probe.callback = try f.eval("(function(p,parent){progress.seen=p;progress.parent=parent;++progress.calls;p.fromHook=37;})");
    probe.install(&f);
    const promise = try f.checked(c.JS_PiNewPendingPromise(f.context.?));
    defer c.JS_FreeValue(f.context.?, promise);
    try probe.expectCount(1);
    try f.set("returned", promise);
    try f.run("if(progress.seen!==returned||progress.parent!==undefined||progress.calls!==1||returned.fromHook!==37)throw Error('init object');");
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(f.context.?, promise));
}
test "VM pending Promise real init hook may settle the same object before allocation returns" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
    probe.settle_value = try f.eval("({fromActualHook:1})");
    probe.settle_in_hook = true; probe.retain_result = true; probe.install(&f);
    const promise = try f.checked(c.JS_PiNewPendingPromise(f.context.?));
    defer c.JS_FreeValue(f.context.?, promise);
    try probe.expectCount(1);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, promise, probe.observations[0].retained));
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(f.context.?, promise));
    const result = c.JS_PromiseResult(f.context.?, promise); defer c.JS_FreeValue(f.context.?, result);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, result, probe.settle_value));
    try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
}
test "VM pending Promise ordinary hook failure preserves its exact reason and an independently retained result" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
    try probe.reason(&f, 0, false); try probe.makeMarker(&f);
    probe.hook_reason = 0; probe.retain_result = true; probe.install(&f);
    const failed = c.JS_PiNewPendingPromise(f.context.?); defer c.JS_FreeValue(f.context.?, failed);
    try std.testing.expect(c.JS_IsException(failed));
    const reason = try f.pending(); defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, reason, probe.reasons[0]));
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    try probe.expectCount(1);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(f.context.?, probe.observations[0].retained));
    try std.testing.expectEqual(@as(usize, 0), probe.retirements);
    const retained = probe.observations[0].retained;
    probe.observations[0].retained = c.pi_js_undefined();
    c.JS_FreeValue(f.context.?, retained);
    try std.testing.expectEqual(@as(usize, 1), probe.retirements);
    try std.testing.expect(!c.JS_HasException(f.context.?));
}
test "VM pending Promise actual fatal init throw stops guest catch and finally and retires the unretained result" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
    try installAllocator(&f);
    try probe.reason(&f, 0, true); try probe.makeMarker(&f);
    try f.set("actualFatal", probe.reasons[0]);
    try f.run("globalThis.progress={getAfter:false,returned:false,caught:false,finalized:false};");
    const progress = try f.eval("progress"); defer c.JS_FreeValue(f.context.?, progress);
    probe.callback = try f.eval("(function(){throw actualFatal;progress.getAfter=true;})");
    probe.install(&f);
    const program: [:0]const u8 =
        "try{allocate();progress.returned=true;}catch(e){progress.caught=true;}finally{progress.finalized=true;}";
    const failed = c.JS_Eval(f.context.?, program.ptr, program.len,
        "actual-pending-promise-fatal.js", c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_STRICT);
    defer c.JS_FreeValue(f.context.?, failed);
    try std.testing.expect(c.JS_IsException(failed));
    const reason = try f.pending(); defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, reason, probe.reasons[0]));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try probe.expectCount(1);
    try std.testing.expectEqual(@as(usize, 1), probe.retirements);
    inline for (.{ "getAfter", "returned", "caught", "finalized" }) |name|
        try f.ownBool(progress, name, false);
}

test "VM pending Promise existing ordinary or fatal pending wins before allocation and the real init hook" {
    inline for (.{ false, true }) |fatal| {
        var probe: Probe = .{};
        var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
        try probe.reason(&f, 0, fatal);
        probe.install(&f);
        const baseline = f.objects();
        _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, probe.reasons[0]));
        c.JS_SetMemoryLimit(f.runtime.?, 1);
        const failed = c.JS_PiNewPendingPromise(f.context.?);
        defer c.JS_FreeValue(f.context.?, failed);
        c.JS_SetMemoryLimit(f.runtime.?, 0);
        try std.testing.expect(c.JS_IsException(failed));
        const reason = try f.pending(); defer c.JS_FreeValue(f.context.?, reason);
        try std.testing.expect(c.JS_IsStrictEqual(f.context.?, reason, probe.reasons[0]));
        try std.testing.expectEqual(fatal, c.JS_IsUncatchableError(reason));
        try probe.expectCount(0);
        try std.testing.expectEqual(baseline, f.objects());
        try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
    }
}
test "VM pending Promise actual heap allocation failure reports pending null without init or leaked objects" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
    probe.install(&f);
    const objects = f.objects();
    const used = c.pi_js_native_memory_used(f.memory);
    c.JS_SetMemoryLimit(f.runtime.?, 1);
    const failed = c.JS_PiNewPendingPromise(f.context.?);
    defer c.JS_FreeValue(f.context.?, failed);
    c.JS_SetMemoryLimit(f.runtime.?, 0);
    try std.testing.expect(c.JS_IsException(failed));
    const reason = try f.pending(); defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(c.JS_IsNull(reason));
    try probe.expectCount(0);
    try std.testing.expectEqual(objects, f.objects());
    try std.testing.expectEqual(used, c.pi_js_native_memory_used(f.memory));
    try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
}
test "VM pending Promise ordinary hook failure yields to an actual result-retirement fatal" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
    try probe.reason(&f, 0, false); try probe.reason(&f, 1, true); try probe.makeMarker(&f);
    probe.hook_reason = 0; probe.cleanup_reason = 1; probe.install(&f);
    const baseline = f.objects();
    const failed = c.JS_PiNewPendingPromise(f.context.?); defer c.JS_FreeValue(f.context.?, failed);
    try std.testing.expect(c.JS_IsException(failed));
    const reason = try f.pending(); defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, reason, probe.reasons[1]));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try probe.expectCount(1);
    try std.testing.expectEqual(@as(usize, 1), probe.retirements);
    // The preexisting marker moved into the failing result and retired with it.
    try std.testing.expectEqual(baseline - 1, f.objects());
    try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
}
test "VM pending Promise first actual init fatal survives a later actual result-retirement fatal" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
    try probe.reason(&f, 0, true); try probe.reason(&f, 1, true); try probe.makeMarker(&f);
    probe.hook_reason = 0; probe.cleanup_reason = 1; probe.install(&f);
    const baseline = f.objects();
    const failed = c.JS_PiNewPendingPromise(f.context.?); defer c.JS_FreeValue(f.context.?, failed);
    try std.testing.expect(c.JS_IsException(failed));
    const reason = try f.pending(); defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, reason, probe.reasons[0]));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try probe.expectCount(1);
    try std.testing.expectEqual(@as(usize, 1), probe.retirements);
    try std.testing.expectEqual(baseline - 1, f.objects());
    try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
}
test "VM pending Promise disabled execution permits intrinsic allocation but guards the real guest init callback" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
    try f.run("globalThis.progress={entered:false};");
    const progress = try f.eval("progress"); defer c.JS_FreeValue(f.context.?, progress);
    probe.callback = try f.eval("(function(){progress.entered=true;})");
    try probe.makeMarker(&f);
    const previous = c.JS_PiExchangeJavascriptExecutionAllowed(f.runtime.?, false);
    defer { _ = c.JS_PiExchangeJavascriptExecutionAllowed(f.runtime.?, previous); }
    // No hook is installed yet: creating the actual intrinsic is not JSEntry.
    const plain = try f.checked(c.JS_PiNewPendingPromise(f.context.?));
    defer c.JS_FreeValue(f.context.?, plain);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(f.context.?, plain));
    probe.install(&f);
    const failed = c.JS_PiNewPendingPromise(f.context.?); defer c.JS_FreeValue(f.context.?, failed);
    try std.testing.expect(c.JS_IsException(failed));
    const reason = try f.pending(); defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(c.JS_IsString(reason));
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    try probe.expectCount(1);
    try f.ownBool(progress, "entered", false);
    try std.testing.expectEqual(@as(usize, 1), probe.retirements);
    try std.testing.expect(!c.JS_PiExchangeJavascriptExecutionAllowed(f.runtime.?, previous));
    try f.run("if(progress.entered)throw Error('guest hook escaped guard');");
}

test "VM pending Promise returned object uses real thenable adoption and reaction settlement" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run(
        \\globalThis.progress={trace:[],value:null};
        \\globalThis.payload={identity:1};
        \\globalThis.thenable={get then(){progress.trace.push("get");return function(resolve){
        \\ if(this!==thenable)throw Error("then receiver");progress.trace.push("call");resolve(payload);
        \\};}};
    );
    const promise = try f.checked(c.JS_PiNewPendingPromise(f.context.?)); defer c.JS_FreeValue(f.context.?, promise);
    const thenable = try f.eval("thenable"); defer c.JS_FreeValue(f.context.?, thenable);
    const payload = try f.eval("payload"); defer c.JS_FreeValue(f.context.?, payload);
    const on_fulfilled = try f.eval("(function(value){progress.trace.push('reaction');progress.value=value;return 11;})");
    defer c.JS_FreeValue(f.context.?, on_fulfilled);
    const derived = try f.checked(c.JS_PromiseThen(f.context.?, promise, on_fulfilled, c.pi_js_undefined()));
    defer c.JS_FreeValue(f.context.?, derived);
    const settled = try f.checked(c.JS_PiSettlePromise(f.context.?, promise, thenable, false));
    defer c.JS_FreeValue(f.context.?, settled);
    try std.testing.expect(c.JS_IsUndefined(settled));
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(f.context.?, promise));
    try f.run("if(progress.trace.join(',')!=='get')throw Error('adoption ran inline');");
    try std.testing.expectEqual(@as(usize, 2), try f.drain());
    const result = c.JS_PromiseResult(f.context.?, promise); defer c.JS_FreeValue(f.context.?, result);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, result, payload));
    const derived_result = c.JS_PromiseResult(f.context.?, derived); defer c.JS_FreeValue(f.context.?, derived_result);
    try f.number(derived_result, 11);
    try f.run("if(progress.value!==payload||progress.trace.join(',')!=='get,call,reaction')throw Error('settlement path');");
}
test "VM pending Promise foreign context selects its own intrinsic prototype and actual init context" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
    const foreign = c.JS_NewContext(f.runtime.?) orelse return error.OutOfMemory;
    defer c.JS_FreeContext(foreign);
    const source: [:0]const u8 = "Promise.prototype";
    const prototype = try f.checked(c.JS_Eval(foreign, source.ptr, source.len,
        "actual-foreign-promise.js", c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_STRICT));
    defer c.JS_FreeValue(foreign, prototype);
    const original_prototype = try f.eval("Promise.prototype"); defer c.JS_FreeValue(f.context.?, original_prototype);
    try std.testing.expect(!c.JS_IsStrictEqual(f.context.?, prototype, original_prototype));
    probe.install(&f);
    const promise = try f.checked(c.JS_PiNewPendingPromise(foreign)); defer c.JS_FreeValue(foreign, promise);
    const actual = try f.checked(c.JS_GetPrototype(foreign, promise)); defer c.JS_FreeValue(foreign, actual);
    try std.testing.expect(c.JS_IsStrictEqual(foreign, prototype, actual));
    try probe.expectCount(1);
    try std.testing.expect(probe.observations[0].context == foreign);
    try std.testing.expect(c.JS_IsUndefined(probe.observations[0].parent));
}
test "VM pending Promise marked hook DATA stays data and original resolving functions retain their one-shot latch" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
    try probe.reason(&f, 0, true);
    try f.set("actualData", probe.reasons[0]);
    probe.callback = try f.eval("(function(p){p.actualData=actualData;return actualData;})");
    probe.install(&f);
    const promise = try f.checked(c.JS_PiNewPendingPromise(f.context.?)); defer c.JS_FreeValue(f.context.?, promise);
    const actual = try f.checked(c.JS_GetPropertyStr(f.context.?, promise, "actualData"));
    defer c.JS_FreeValue(f.context.?, actual);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, actual, probe.reasons[0]));
    try std.testing.expect(c.JS_IsUncatchableError(actual));
    try std.testing.expect(!c.JS_HasException(f.context.?));
    c.JS_SetPromiseHook(f.runtime.?, null, null);
    const data_result = try f.checked(c.JS_PiSettlePromise(f.context.?, promise, actual, true));
    defer c.JS_FreeValue(f.context.?, data_result);
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(f.context.?, promise));
    const rejection = c.JS_PromiseResult(f.context.?, promise); defer c.JS_FreeValue(f.context.?, rejection);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, rejection, actual));
    try std.testing.expect(!c.JS_HasException(f.context.?));
    var resolving = [_]c.JSValue{ c.pi_js_undefined(), c.pi_js_undefined() };
    const original = try f.checked(c.JS_NewPromiseCapability(f.context.?, &resolving));
    defer c.JS_FreeValue(f.context.?, original);
    defer { for (resolving) |value| c.JS_FreeValue(f.context.?, value); }
    const first_arg = [_]c.JSValue{c.pi_js_int32(f.context.?, 7)};
    const second_arg = [_]c.JSValue{c.pi_js_int32(f.context.?, 9)};
    const first = try f.checked(c.JS_Call(f.context.?, resolving[0], c.pi_js_undefined(), 1, @constCast(&first_arg)));
    defer c.JS_FreeValue(f.context.?, first);
    const second = try f.checked(c.JS_Call(f.context.?, resolving[1], c.pi_js_undefined(), 1, @constCast(&second_arg)));
    defer c.JS_FreeValue(f.context.?, second);
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(f.context.?, original));
    const original_result = c.JS_PromiseResult(f.context.?, original); defer c.JS_FreeValue(f.context.?, original_result);
    try f.number(original_result, 7);
}

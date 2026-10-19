//! Raw VM controls for Node's V8 THROW_ON_FAILURE execution scope semantics.
//! Real native API callbacks are explicitly admitted; native Source bodies are
//! never exempted merely because they are implemented in C. These controls use
//! actual linked call/constructor/Promise jobs, not an Engine-only entry check.
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
            _ = c.JS_PiExchangeJavascriptExecutionAllowed(runtime, true);
            c.JS_SetExecutionContextHook(runtime, null, null);
            c.JS_SetPromiseHook(runtime, null, null);
        }
        if (self.context) |context| { self.context = null; c.JS_FreeContext(context); }
        if (self.runtime) |runtime| { self.runtime = null; c.JS_FreeRuntime(runtime); }
        if (self.memory) |memory| { self.memory = null; c.pi_js_release_memory_owner(memory); }
    }
    fn checked(self: *Fixture, value: c.JSValue) !c.JSValue {
        if (c.JS_IsException(value) or c.JS_HasException(self.context.?)) {
            if (!c.JS_IsException(value)) c.JS_FreeValue(self.context.?, value);
            const reason = c.JS_GetException(self.context.?);
            c.JS_FreeValue(self.context.?, reason);
            return error.ActualDisallowJavascriptControlException;
        }
        return value;
    }
    fn evalRaw(self: *Fixture, source: [:0]const u8) c.JSValue {
        return c.JS_Eval(self.context.?, source.ptr, source.len, "actual-disallow-javascript.js",
            c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_STRICT);
    }
    fn eval(self: *Fixture, source: [:0]const u8) !c.JSValue { return self.checked(self.evalRaw(source)); }
    fn run(self: *Fixture, source: [:0]const u8) !void {
        const value = try self.eval(source); defer c.JS_FreeValue(self.context.?, value);
    }
    fn set(self: *Fixture, key: [*:0]const u8, value: c.JSValue) !void {
        const global_object = try self.checked(c.JS_GetGlobalObject(self.context.?));
        defer c.JS_FreeValue(self.context.?, global_object);
        if (c.JS_SetPropertyStr(self.context.?, global_object, key, c.JS_DupValue(self.context.?, value)) < 0)
            return error.ActualDisallowJavascriptPublishFailure;
        try std.testing.expect(!c.JS_HasException(self.context.?));
    }
    fn exception(self: *Fixture, result: c.JSValue) !c.JSValue {
        try std.testing.expect(c.JS_IsException(result));
        try std.testing.expect(c.JS_HasException(self.context.?));
        return c.JS_GetException(self.context.?);
    }
    fn pendingReason(self: *Fixture) !c.JSValue {
        try std.testing.expect(c.JS_HasException(self.context.?));
        return c.JS_GetException(self.context.?);
    }
    fn illegal(self: *Fixture, reason: c.JSValue) !void {
        try std.testing.expect(c.JS_IsString(reason));
        try std.testing.expect(!c.JS_IsError(reason));
        try std.testing.expect(!c.JS_IsUncatchableError(reason));
        const bytes = c.JS_ToCString(self.context.?, reason) orelse return error.OutOfMemory;
        defer c.JS_FreeCString(self.context.?, bytes);
        try std.testing.expectEqualStrings("illegal access", std.mem.span(bytes));
    }
    fn ownBool(self: *Fixture, record: c.JSValue, key: [*:0]const u8, expected: bool) !void {
        // Every caller retained this exact plain own-data record before failure.
        const value = c.JS_GetPropertyStr(self.context.?, record, key);
        defer c.JS_FreeValue(self.context.?, value);
        try std.testing.expect(c.JS_IsBool(value));
        try std.testing.expectEqual(@as(c_int, @intFromBool(expected)), c.JS_ToBool(self.context.?, value));
    }
    fn ownNumber(self: *Fixture, record: c.JSValue, key: [*:0]const u8, expected: i32) !void {
        const value = c.JS_GetPropertyStr(self.context.?, record, key);
        defer c.JS_FreeValue(self.context.?, value);
        try self.numberValue(value, expected);
    }
    fn numberValue(self: *Fixture, value: c.JSValue, expected: i32) !void {
        try std.testing.expect(c.JS_IsNumber(value));
        var observed: i32 = 0;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(self.context.?, &observed, value));
        try std.testing.expectEqual(expected, observed);
    }
    fn call(self: *Fixture, function: c.JSValue) c.JSValue {
        return c.JS_Call(self.context.?, function, c.pi_js_undefined(), 0, null);
    }
    fn api(self: *Fixture, callback: *const c.JSCFunctionData, name: [*:0]const u8,
        data: []const c.JSValue) !c.JSValue
    {
        const function = try self.checked(c.JS_NewCFunctionData2(self.context.?, callback, name, 0, 0,
            @intCast(data.len), if (data.len == 0) null else @constCast(data.ptr)));
        errdefer c.JS_FreeValue(self.context.?, function);
        try std.testing.expectEqual(@as(c_int, 0), c.JS_PiMarkNativeApiFunction(self.context.?, function));
        return function;
    }
    fn drain(self: *Fixture) !usize {
        var count: usize = 0;
        while (c.JS_IsJobPending(self.runtime.?)) {
            if (count == 64) return error.ActualDisallowJavascriptJobBudget;
            var context: ?*c.JSContext = null;
            const status = c.JS_ExecutePendingJob(self.runtime.?, &context);
            // A zero result is a genuine no-progress checkpoint, never a reason
            // to spin solely on JS_IsJobPending.
            if (status == 0) return count;
            if (status < 0 or c.JS_HasException(context orelse self.context.?)) {
                const reason = c.JS_GetException(context orelse self.context.?);
                c.JS_FreeValue(context orelse self.context.?, reason);
                return error.ActualDisallowJavascriptJobFailure;
            }
            try std.testing.expectEqual(@as(c_int, 1), status);
            count += 1;
        }
        c.JS_ClearKeptObjects(self.runtime.?);
        return count;
    }
};
const Scope = struct {
    runtime: *c.JSRuntime,
    previous: bool,
    fn enter(f: *Fixture) Scope {
        return .{ .runtime = f.runtime.?, .previous = c.JS_PiExchangeJavascriptExecutionAllowed(f.runtime.?, false) };
    }
    fn restore(self: Scope) void { _ = c.JS_PiExchangeJavascriptExecutionAllowed(self.runtime, self.previous); }
};
const Token = struct { probe: *Probe, index: usize };
const Probe = struct {
    calls: usize = 0,
    after_nested: usize = 0,
    class_calls: usize = 0,
    prototype_gets: usize = 0,
    async_starts: usize = 0,
    async_resumes: usize = 0,
    job_calls: usize = 0,
    promise_inits: usize = 0,
    hook_before: usize = 0,
    hook_after: usize = 0,
    hook_mismatch: bool = false,
    hook_expected: c.JSValue = undefined,
    counts: [3]usize = .{ 0, 0, 0 },
    tokens: [3]Token = undefined,
    class_id: c.JSClassID = 0,
    fn init(self: *Probe, f: *Fixture) !void {
        self.hook_expected = c.pi_js_undefined();
        for (&self.tokens, 0..) |*token, index| token.* = .{ .probe = self, .index = index };
        c.JS_SetContextOpaque(f.context.?, self);
        _ = c.JS_NewClassID(f.runtime.?, &self.class_id);
        const class_definition: c.JSClassDef = .{ .class_name = "Actual execution scope holder", .finalizer = retire };
        try std.testing.expectEqual(@as(c_int, 0), c.JS_NewClass(f.runtime.?, self.class_id, &class_definition));
    }
    fn from(context: ?*c.JSContext) ?*Probe {
        const ctx = context orelse return null;
        const raw_owner = c.JS_GetContextOpaque(ctx) orelse return null;
        return @ptrCast(@alignCast(raw_owner));
    }
    fn retire(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
        const raw_owner = c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return;
        const token: *Token = @ptrCast(@alignCast(raw_owner));
        _ = c.JS_SetOpaque(value, null);
        token.probe.counts[token.index] += 1;
    }
    fn holder(self: *Probe, f: *Fixture, index: usize) !c.JSValue {
        const value = try f.checked(c.JS_NewObjectProtoClass(f.context.?, c.pi_js_null(), self.class_id));
        _ = c.JS_SetOpaque(value, &self.tokens[index]);
        return value;
    }
    fn attach(self: *Probe, f: *Fixture, value: c.JSValue, index: usize) !void {
        const marker = try self.holder(f, index);
        try std.testing.expectEqual(@as(c_int, 1), c.JS_DefinePropertyValueStr(f.context.?, value,
            "actualScopeHolder", marker, c.JS_PROP_C_W_E));
        try std.testing.expect(!c.JS_HasException(f.context.?));
    }
};
fn nativeReturn(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue,
    _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const ctx = context orelse return c.pi_js_exception();
    const probe = Probe.from(ctx) orelse return c.pi_js_exception();
    probe.calls += 1;
    return if (argc == 0) c.pi_js_int32(ctx, 23) else c.JS_DupValue(ctx, argv[0]);
}
fn nativeDataReturn(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue,
    _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const ctx = context orelse return c.pi_js_exception();
    const probe = Probe.from(ctx) orelse return c.pi_js_exception();
    probe.calls += 1;
    return c.JS_DupValue(ctx, data[0]);
}
fn nativePrototypeTrap(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue,
    _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const ctx = context orelse return c.pi_js_exception();
    const probe = Probe.from(ctx) orelse return c.pi_js_exception();
    probe.prototype_gets += 1;
    return c.JS_DupValue(ctx, data[0]);
}
fn nativeNested(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue,
    _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const ctx = context orelse return c.pi_js_exception();
    const probe = Probe.from(ctx) orelse return c.pi_js_exception();
    probe.calls += 1;
    const value = c.JS_Call(ctx, data[0], c.pi_js_undefined(), 0, null);
    if (c.JS_IsException(value)) return value;
    probe.after_nested += 1;
    return value;
}
fn nativeClass(context: ?*c.JSContext, _: c.JSValue, _: c.JSValue, _: c_int,
    _: [*c]c.JSValue, flags: c_int) callconv(.c) c.JSValue
{
    const ctx = context orelse return c.pi_js_exception();
    const probe = Probe.from(ctx) orelse return c.pi_js_exception();
    probe.class_calls += 1;
    if ((flags & c.JS_CALL_FLAG_CONSTRUCTOR) != 0) return c.JS_NewObjectProto(ctx, c.pi_js_null());
    return c.pi_js_int32(ctx, 31);
}
fn nativeConstructor(context: ?*c.JSContext, new_target: c.JSValue, _: c_int, _: [*c]c.JSValue,
    _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const ctx = context orelse return c.pi_js_exception();
    const probe = Probe.from(ctx) orelse return c.pi_js_exception();
    probe.calls += 1;
    const prototype = c.JS_PiGetObjectPrototypeFromConstructor(ctx, new_target);
    if (c.JS_IsException(prototype)) return prototype;
    defer c.JS_FreeValue(ctx, prototype);
    return c.JS_NewObjectProto(ctx, prototype);
}
fn nativeFatalThenCall(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue,
    _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const ctx = context orelse return c.pi_js_exception();
    const probe = Probe.from(ctx) orelse return c.pi_js_exception();
    probe.calls += 1;
    _ = c.JS_Throw(ctx, c.JS_DupValue(ctx, data[0]));
    // The second real entry must preserve the already published fatal, not
    // manufacture the ordinary disallow string or visit data[1]'s body.
    return c.JS_Call(ctx, data[1], c.pi_js_undefined(), 0, null);
}
fn nativeScopeCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue,
    _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const ctx = context orelse return c.pi_js_exception();
    if (argc == 0) return c.JS_ThrowTypeError(ctx, "scope callback requires its actual callee");
    const runtime = c.JS_GetRuntime(ctx);
    const previous = c.JS_PiExchangeJavascriptExecutionAllowed(runtime, false);
    defer _ = c.JS_PiExchangeJavascriptExecutionAllowed(runtime, previous);
    return c.JS_Call(ctx, argv[0], c.pi_js_undefined(), 0, null);
}
fn nativeAsync(context: ?*c.JSContext, _: c.JSValue, _: c.JSValue, argc: c_int,
    argv: [*c]c.JSValue, completion: c_int, input: c.JSValue,
    _: [*c]c.JSValue, action: [*c]c_int) callconv(.c) c.JSValue
{
    const ctx = context orelse return c.pi_js_exception();
    const probe = Probe.from(ctx) orelse return c.pi_js_exception();
    if (completion == c.JS_PI_AF_START) {
        probe.async_starts += 1;
        if (argc > 0) { action[0] = c.JS_PI_AF_AWAIT; return c.JS_DupValue(ctx, argv[0]); }
        action[0] = c.JS_PI_AF_RETURN;
        return c.pi_js_int32(ctx, 41);
    }
    probe.async_resumes += 1;
    action[0] = c.JS_PI_AF_RETURN;
    return c.JS_DupValue(ctx, input);
}
fn nativeJob(context: ?*c.JSContext, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const ctx = context orelse return c.pi_js_exception();
    const probe = Probe.from(ctx) orelse return c.pi_js_exception();
    probe.job_calls += 1;
    return c.pi_js_undefined();
}
fn promiseHook(_: ?*c.JSContext, kind: c.JSPromiseHookType, _: c.JSValue,
    _: c.JSValue, raw_owner: ?*anyopaque) callconv(.c) void
{
    const raw = raw_owner orelse return;
    const probe: *Probe = @ptrCast(@alignCast(raw));
    if (kind == c.JS_PROMISE_HOOK_INIT) probe.promise_inits += 1;
}
fn contextHook(context: ?*c.JSContext, before: bool, value: c.JSValue, raw_owner: ?*anyopaque) callconv(.c) void {
    const ctx = context orelse return;
    const raw = raw_owner orelse return;
    const probe: *Probe = @ptrCast(@alignCast(raw));
    if (!c.JS_IsStrictEqual(ctx, value, probe.hook_expected)) probe.hook_mismatch = true;
    if (before) probe.hook_before += 1 else probe.hook_after += 1;
}

test "VM DisallowJS saved nested flags restore without allocation or pending replacement" {
    inline for (.{ false, true }) |uncatchable| {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        const reason = try f.checked(c.JS_NewError(f.context.?)); defer c.JS_FreeValue(f.context.?, reason);
        if (uncatchable) c.JS_SetUncatchableError(f.context.?, reason);
        _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, reason));
        c.JS_SetMemoryLimit(f.runtime.?, 1);
        const outer = c.JS_PiExchangeJavascriptExecutionAllowed(f.runtime.?, false);
        const inner = c.JS_PiExchangeJavascriptExecutionAllowed(f.runtime.?, false);
        const allowed = c.JS_PiExchangeJavascriptExecutionAllowed(f.runtime.?, true);
        const prior_restore = c.JS_PiExchangeJavascriptExecutionAllowed(f.runtime.?, allowed);
        const inner_restore = c.JS_PiExchangeJavascriptExecutionAllowed(f.runtime.?, inner);
        const outer_restore = c.JS_PiExchangeJavascriptExecutionAllowed(f.runtime.?, outer);
        c.JS_SetMemoryLimit(f.runtime.?, 0);
        try std.testing.expect(outer and !inner and !allowed and prior_restore and !inner_restore and !outer_restore);
        const observed = try f.pendingReason(); defer c.JS_FreeValue(f.context.?, observed);
        try std.testing.expect(c.JS_IsStrictEqual(f.context.?, reason, observed));
        try std.testing.expect(c.JS_IsUncatchableError(observed) == uncatchable);
        try f.run("globalThis.restoredScope=true;");
    }
}

test "VM DisallowJS raw bytecode call throws its preallocated ordinary string before body" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const function = try f.eval(
        \\globalThis.progress={body:false,error:false};
        \\globalThis.Error=function(){progress.error=true;throw 1;};
        \\(function(){progress.body=true;return 17;})
    ); defer c.JS_FreeValue(f.context.?, function);
    const progress = try f.eval("progress"); defer c.JS_FreeValue(f.context.?, progress);
    {
        const scope = Scope.enter(&f); defer scope.restore();
        c.JS_SetMemoryLimit(f.runtime.?, 1);
        const value = f.call(function);
        c.JS_SetMemoryLimit(f.runtime.?, 0);
        const reason = try f.exception(value); defer c.JS_FreeValue(f.context.?, reason);
        try f.illegal(reason);
        try f.ownBool(progress, "body", false); try f.ownBool(progress, "error", false);
    }
    const value = try f.checked(f.call(function)); defer c.JS_FreeValue(f.context.?, value);
    try f.numberValue(value, 17);
    try f.ownBool(progress, "body", true);
}

test "VM DisallowJS compilation stays native and precompiled execution is guarded" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run("globalThis.progress={body:false};");
    const progress = try f.eval("progress"); defer c.JS_FreeValue(f.context.?, progress);
    const text: [:0]const u8 = "progress.body=true;";
    {
        const scope = Scope.enter(&f); defer scope.restore();
        const compiled = try f.checked(c.JS_Eval(f.context.?, text.ptr, text.len, "actual-blocked-script.js",
            c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_STRICT | c.JS_EVAL_FLAG_COMPILE_ONLY));
        const reason = try f.exception(c.JS_EvalFunction(f.context.?, compiled));
        defer c.JS_FreeValue(f.context.?, reason);
        try f.illegal(reason);
        try f.ownBool(progress, "body", false);
    }
    try f.run("progress.body=true;");
    try f.ownBool(progress, "body", true);
}

test "VM DisallowJS ordinary native implementations and VM builtins are not implicit APIs" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f);
    const native = try f.checked(c.JS_NewCFunctionData(f.context.?, nativeReturn, 0, 0, 0, null));
    defer c.JS_FreeValue(f.context.?, native);
    const builtin = try f.eval("Array.isArray"); defer c.JS_FreeValue(f.context.?, builtin);
    {
        const scope = Scope.enter(&f); defer scope.restore();
        for ([_]c.JSValue{ native, builtin }) |function| {
            const reason = try f.exception(f.call(function)); defer c.JS_FreeValue(f.context.?, reason);
            try f.illegal(reason);
        }
        try std.testing.expectEqual(@as(usize, 0), probe.calls);
    }
    const value = try f.checked(f.call(native)); defer c.JS_FreeValue(f.context.?, value);
    try f.numberValue(value, 23); try std.testing.expectEqual(@as(usize, 1), probe.calls);
}

test "VM DisallowJS direct API admission allocates nothing and preserves callable shape" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f);
    const function = try f.checked(c.JS_NewCFunctionData2(f.context.?, nativeReturn, "ActualAPI", 2, 0, 0, null));
    defer c.JS_FreeValue(f.context.?, function); try f.set("actualAPI", function);
    try f.run(
        \\globalThis.beforeKeys=Reflect.ownKeys(actualAPI);
        \\globalThis.beforeName=Object.getOwnPropertyDescriptor(actualAPI,"name");
        \\globalThis.beforeLength=Object.getOwnPropertyDescriptor(actualAPI,"length");
        \\globalThis.beforePrototype=Object.getPrototypeOf(actualAPI);
    );
    {
        const scope = Scope.enter(&f); defer scope.restore();
        c.JS_SetMemoryLimit(f.runtime.?, 1);
        const status = c.JS_PiMarkNativeApiFunction(f.context.?, function);
        const value = f.call(function);
        c.JS_SetMemoryLimit(f.runtime.?, 0);
        try std.testing.expectEqual(@as(c_int, 0), status);
        const owned = try f.checked(value); defer c.JS_FreeValue(f.context.?, owned);
        try f.numberValue(owned, 23);
    }
    try f.run(
        \\if(Reflect.ownKeys(actualAPI).some((x,i)=>x!==beforeKeys[i])||
        \\ Reflect.ownKeys(actualAPI).length!==beforeKeys.length||
        \\ Object.getPrototypeOf(actualAPI)!==beforePrototype||
        \\ JSON.stringify(Object.getOwnPropertyDescriptor(actualAPI,"name"))!==JSON.stringify(beforeName)||
        \\ JSON.stringify(Object.getOwnPropertyDescriptor(actualAPI,"length"))!==JSON.stringify(beforeLength))
        \\ throw Error("API admission changed public shape");
    );
    try std.testing.expectEqual(@as(usize, 1), probe.calls);
}

test "VM DisallowJS API admission rejects wrappers bytecode async and noncallable brands without traps" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f);
    const api = try f.api(nativeReturn, "ActualAPI", &.{}); defer c.JS_FreeValue(f.context.?, api);
    try f.set("actualAPI", api);
    const subjects = try f.eval(
        \\globalThis.progress={traps:0};
        \\[(function(){}),(async function(){}),(function*(){}),(async function*(){}),
        \\ actualAPI.bind(null),new Proxy(actualAPI,{get(){++progress.traps;throw 1;},
        \\ getPrototypeOf(){++progress.traps;throw 2;}}),{},null]
    ); defer c.JS_FreeValue(f.context.?, subjects);
    const progress = try f.eval("progress"); defer c.JS_FreeValue(f.context.?, progress);
    for (0..8) |index| {
        const subject = try f.checked(c.JS_GetPropertyUint32(f.context.?, subjects, @intCast(index)));
        defer c.JS_FreeValue(f.context.?, subject);
        try std.testing.expectEqual(@as(c_int, -1), c.JS_PiMarkNativeApiFunction(f.context.?, subject));
        const reason = try f.pendingReason(); defer c.JS_FreeValue(f.context.?, reason);
        try std.testing.expect(c.JS_IsError(reason));
    }
    const native_async = try f.checked(c.JS_PiNewNativeAsyncFunction(f.context.?, nativeAsync,
        c.pi_js_undefined(), c.pi_js_undefined(), 0, "ActualSourceAsync", 0));
    defer c.JS_FreeValue(f.context.?, native_async);
    try std.testing.expectEqual(@as(c_int, -1), c.JS_PiMarkNativeApiFunction(f.context.?, native_async));
    const reason = try f.pendingReason(); defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(c.JS_IsError(reason)); try f.ownNumber(progress, "traps", 0);
    try std.testing.expectEqual(@as(usize, 0), probe.async_starts);
}

test "VM DisallowJS callable embedder class admission is private to the actual marked object" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f);
    var class_id: c.JSClassID = 0; _ = c.JS_NewClassID(f.runtime.?, &class_id);
    const class_definition: c.JSClassDef = .{ .class_name = "Actual API class", .call = nativeClass };
    try std.testing.expectEqual(@as(c_int, 0), c.JS_NewClass(f.runtime.?, class_id, &class_definition));
    const function = try f.checked(c.JS_NewObjectProtoClass(f.context.?, c.pi_js_null(), class_id));
    defer c.JS_FreeValue(f.context.?, function);
    const inheritor = try f.checked(c.JS_NewObjectProtoClass(f.context.?, function, class_id));
    defer c.JS_FreeValue(f.context.?, inheritor);
    try std.testing.expectEqual(@as(c_int, 0), c.JS_PiMarkNativeApiFunction(f.context.?, function));
    try std.testing.expect(c.JS_SetConstructorBit(f.context.?, function, true));
    {
        const scope = Scope.enter(&f); defer scope.restore();
        const value = try f.checked(f.call(function)); defer c.JS_FreeValue(f.context.?, value);
        try f.numberValue(value, 31);
        const object = try f.checked(c.JS_CallConstructor(f.context.?, function, 0, null));
        defer c.JS_FreeValue(f.context.?, object); try std.testing.expect(c.JS_IsObject(object));
        const reason = try f.exception(f.call(inheritor)); defer c.JS_FreeValue(f.context.?, reason);
        try f.illegal(reason);
    }
    try std.testing.expectEqual(@as(usize, 2), probe.class_calls);
}

test "VM DisallowJS admitted native callback reaches the genuine nested JavaScript guard" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f);
    const nested = try f.eval("globalThis.progress={body:false};(function(){progress.body=true;return 19;})");
    defer c.JS_FreeValue(f.context.?, nested);
    const progress = try f.eval("progress"); defer c.JS_FreeValue(f.context.?, progress);
    const api = try f.api(nativeNested, "ActualNestedAPI", &.{nested}); defer c.JS_FreeValue(f.context.?, api);
    {
        const scope = Scope.enter(&f); defer scope.restore();
        const reason = try f.exception(f.call(api)); defer c.JS_FreeValue(f.context.?, reason);
        try f.illegal(reason); try f.ownBool(progress, "body", false);
        try std.testing.expectEqual(@as(usize, 1), probe.calls);
        try std.testing.expectEqual(@as(usize, 0), probe.after_nested);
    }
    const result = try f.checked(f.call(api)); defer c.JS_FreeValue(f.context.?, result);
    try f.numberValue(result, 19); try f.ownBool(progress, "body", true);
    try std.testing.expectEqual(@as(usize, 1), probe.after_nested);
}

test "VM DisallowJS live defined accessors are guarded while native APIs and data remain available" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f);
    const object = try f.eval(
        \\globalThis.progress={get:false,set:false};({plain:1,
        \\ get source(){progress.get=true;return 2;},set source(v){progress.set=true;}})
    ); defer c.JS_FreeValue(f.context.?, object);
    const progress = try f.eval("progress"); defer c.JS_FreeValue(f.context.?, progress);
    const getter = try f.api(nativeReturn, "ActualGetter", &.{}); defer c.JS_FreeValue(f.context.?, getter);
    const setter = try f.api(nativeReturn, "ActualSetter", &.{}); defer c.JS_FreeValue(f.context.?, setter);
    const atom = c.JS_NewAtom(f.context.?, "native"); defer c.JS_FreeAtom(f.context.?, atom);
    try std.testing.expect(atom != c.JS_ATOM_NULL);
    try std.testing.expectEqual(@as(c_int, 1), c.JS_DefinePropertyGetSet(f.context.?, object, atom,
        c.JS_DupValue(f.context.?, getter), c.JS_DupValue(f.context.?, setter), c.JS_PROP_CONFIGURABLE));
    {
        const scope = Scope.enter(&f); defer scope.restore();
        const get_reason = try f.exception(c.JS_GetPropertyStr(f.context.?, object, "source"));
        defer c.JS_FreeValue(f.context.?, get_reason); try f.illegal(get_reason);
        try std.testing.expectEqual(@as(c_int, -1), c.JS_SetPropertyStr(f.context.?, object, "source", c.pi_js_int32(f.context.?, 4)));
        const set_reason = try f.pendingReason(); defer c.JS_FreeValue(f.context.?, set_reason); try f.illegal(set_reason);
        const native_value = try f.checked(c.JS_GetPropertyStr(f.context.?, object, "native"));
        defer c.JS_FreeValue(f.context.?, native_value); try f.numberValue(native_value, 23);
        try std.testing.expectEqual(@as(c_int, 1), c.JS_SetPropertyStr(f.context.?, object, "native", c.pi_js_int32(f.context.?, 7)));
        try std.testing.expectEqual(@as(c_int, 1), c.JS_SetPropertyStr(f.context.?, object, "plain", c.pi_js_int32(f.context.?, 9)));
        const plain = try f.checked(c.JS_GetPropertyStr(f.context.?, object, "plain"));
        defer c.JS_FreeValue(f.context.?, plain); try f.numberValue(plain, 9);
        try f.ownBool(progress, "get", false); try f.ownBool(progress, "set", false);
    }
    try std.testing.expectEqual(@as(usize, 2), probe.calls);
}

test "VM DisallowJS proxy property operations distinguish absent native and JavaScript traps" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f);
    const api = try f.api(nativeReturn, "ActualTrap", &.{}); defer c.JS_FreeValue(f.context.?, api);
    try f.set("actualTrap", api);
    const subjects = try f.eval(
        \\globalThis.progress={trap:false,getter:false};
        \\[new Proxy({value:17},{}),
        \\ new Proxy({value:17},{get:actualTrap}),
        \\ new Proxy({value:17},{get(){progress.trap=true;return 31;}}),
        \\ new Proxy({value:17},{get get(){progress.getter=true;return actualTrap;}})]
    ); defer c.JS_FreeValue(f.context.?, subjects);
    const progress = try f.eval("progress"); defer c.JS_FreeValue(f.context.?, progress);
    var values: [4]c.JSValue = undefined;
    for (&values) |*value| value.* = c.pi_js_undefined();
    defer for (values) |value| c.JS_FreeValue(f.context.?, value);
    for (&values, 0..) |*value, index| value.* = try f.checked(c.JS_GetPropertyUint32(f.context.?, subjects, @intCast(index)));
    {
        const scope = Scope.enter(&f); defer scope.restore();
        const plain = try f.checked(c.JS_GetPropertyStr(f.context.?, values[0], "value"));
        defer c.JS_FreeValue(f.context.?, plain); try f.numberValue(plain, 17);
        // The real get trap receives target/key/receiver. nativeReturn returns
        // its borrowed first argument, proving the actual native trap ran.
        const native_value = try f.checked(c.JS_GetPropertyStr(f.context.?, values[1], "value"));
        defer c.JS_FreeValue(f.context.?, native_value); try std.testing.expect(c.JS_IsObject(native_value));
        for (values[2..]) |value| {
            const reason = try f.exception(c.JS_GetPropertyStr(f.context.?, value, "value"));
            defer c.JS_FreeValue(f.context.?, reason); try f.illegal(reason);
        }
        try f.ownBool(progress, "trap", false); try f.ownBool(progress, "getter", false);
    }
    try std.testing.expectEqual(@as(usize, 1), probe.calls);
}

test "VM DisallowJS bound and callable proxy API wrappers do not inherit the direct exemption" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f);
    const api = try f.api(nativeReturn, "ActualAPI", &.{}); defer c.JS_FreeValue(f.context.?, api);
    try f.set("actualAPI", api);
    const bound = try f.eval("actualAPI.bind(null)"); defer c.JS_FreeValue(f.context.?, bound);
    const getter = try f.api(nativeDataReturn, "ActualApplyGetter", &.{api});
    defer c.JS_FreeValue(f.context.?, getter); try f.set("actualApplyGetter", getter);
    const proxy = try f.eval(
        \\const handler={};Object.defineProperty(handler,"apply",{get:actualApplyGetter});
        \\new Proxy(actualAPI,handler)
    ); defer c.JS_FreeValue(f.context.?, proxy);
    {
        const scope = Scope.enter(&f); defer scope.restore();
        for ([_]c.JSValue{ bound, proxy }) |function| {
            const reason = try f.exception(f.call(function)); defer c.JS_FreeValue(f.context.?, reason); try f.illegal(reason);
        }
        // A marked native getter would run under this scope if the outer
        // Proxy dispatch incorrectly reached GetMethod(handler, "apply").
        try std.testing.expectEqual(@as(usize, 0), probe.calls);
    }
    const value = try f.checked(f.call(bound)); defer c.JS_FreeValue(f.context.?, value);
    try f.numberValue(value, 23);
}

test "VM DisallowJS constructor guard precedes newTarget prototype while direct native construction remains real" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f);
    const source = try f.eval("globalThis.progress={body:false};(function(){progress.body=true;})");
    defer c.JS_FreeValue(f.context.?, source);
    const prototype = try f.eval("({actualPrototype:true})"); defer c.JS_FreeValue(f.context.?, prototype);
    const trap = try f.api(nativePrototypeTrap, "ActualPrototypeTrap", &.{prototype});
    defer c.JS_FreeValue(f.context.?, trap); try f.set("actualPrototypeTrap", trap);
    const new_target = try f.eval("new Proxy(function(){},{get:actualPrototypeTrap})");
    defer c.JS_FreeValue(f.context.?, new_target);
    const progress = try f.eval("progress"); defer c.JS_FreeValue(f.context.?, progress);
    const native = try f.api(nativeConstructor, "ActualConstructor", &.{}); defer c.JS_FreeValue(f.context.?, native);
    try std.testing.expect(c.JS_SetConstructorBit(f.context.?, native, true));
    {
        const scope = Scope.enter(&f); defer scope.restore();
        const reason = try f.exception(c.JS_CallConstructor2(f.context.?, source, new_target, 0, null));
        defer c.JS_FreeValue(f.context.?, reason); try f.illegal(reason);
        try f.ownBool(progress, "body", false);
        try std.testing.expectEqual(@as(usize, 0), probe.prototype_gets);
        // The native API really enters and uses GetPrototypeFromConstructor.
        // Its selected native trap is permitted; no replacement prototype path.
        const object = try f.checked(c.JS_CallConstructor2(f.context.?, native, new_target, 0, null));
        defer c.JS_FreeValue(f.context.?, object);
        const actual_prototype = try f.checked(c.JS_GetPrototype(f.context.?, object));
        defer c.JS_FreeValue(f.context.?, actual_prototype);
        try std.testing.expect(c.JS_IsStrictEqual(f.context.?, prototype, actual_prototype));
        try std.testing.expectEqual(@as(usize, 1), probe.calls);
        try std.testing.expectEqual(@as(usize, 1), probe.prototype_gets);
        const ordinary = try f.checked(c.JS_CallConstructor(f.context.?, native, 0, null));
        defer c.JS_FreeValue(f.context.?, ordinary); try std.testing.expect(c.JS_IsObject(ordinary));
    }
    try std.testing.expectEqual(@as(usize, 2), probe.calls);
}

test "VM DisallowJS scope is shared by genuine contexts in one runtime" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const foreign = c.JS_NewContext(f.runtime.?) orelse return error.OutOfMemory;
    defer c.JS_FreeContext(foreign);
    const text: [:0]const u8 = "globalThis.visits=0;(function(){++visits;return 47;})";
    const function = c.JS_Eval(foreign, text.ptr, text.len, "actual-foreign-scope.js",
        c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_STRICT);
    try std.testing.expect(!c.JS_IsException(function)); defer c.JS_FreeValue(foreign, function);
    const global_object = c.JS_GetGlobalObject(foreign); defer c.JS_FreeValue(foreign, global_object);
    {
        const scope = Scope.enter(&f); defer scope.restore();
        const reason = try f.exception(c.JS_Call(foreign, function, c.pi_js_undefined(), 0, null));
        defer c.JS_FreeValue(foreign, reason); try f.illegal(reason);
        try f.ownNumber(global_object, "visits", 0);
    }
    const value = try f.checked(c.JS_Call(foreign, function, c.pi_js_undefined(), 0, null));
    defer c.JS_FreeValue(foreign, value); try f.numberValue(value, 47);
    try f.ownNumber(global_object, "visits", 1);
}

test "VM DisallowJS genuine native AsyncFunction initial entry precedes body and capability creation" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f);
    const function = try f.checked(c.JS_PiNewNativeAsyncFunction(f.context.?, nativeAsync,
        c.pi_js_undefined(), c.pi_js_undefined(), 0, "ActualSourceAsync", 0));
    defer c.JS_FreeValue(f.context.?, function);
    c.JS_SetPromiseHook(f.runtime.?, promiseHook, &probe);
    {
        const scope = Scope.enter(&f); defer scope.restore();
        c.JS_SetMemoryLimit(f.runtime.?, 1);
        const result = f.call(function);
        c.JS_SetMemoryLimit(f.runtime.?, 0);
        const reason = try f.exception(result); defer c.JS_FreeValue(f.context.?, reason); try f.illegal(reason);
        try std.testing.expectEqual(@as(usize, 0), probe.async_starts);
        try std.testing.expectEqual(@as(usize, 0), probe.promise_inits);
        try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
    }
    const promise = try f.checked(f.call(function)); defer c.JS_FreeValue(f.context.?, promise);
    try std.testing.expect(c.JS_PromiseState(f.context.?, promise) == c.JS_PROMISE_FULFILLED);
    const value = c.JS_PromiseResult(f.context.?, promise); defer c.JS_FreeValue(f.context.?, value);
    try f.numberValue(value, 41);
    try std.testing.expectEqual(@as(usize, 1), probe.async_starts);
    try std.testing.expectEqual(@as(usize, 1), probe.promise_inits);
}

test "VM DisallowJS suspended native AsyncFunction keeps its actual Await queued until restoration" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f);
    const function = try f.checked(c.JS_PiNewNativeAsyncFunction(f.context.?, nativeAsync,
        c.pi_js_undefined(), c.pi_js_undefined(), 0, "ActualAwaitSource", 1));
    defer c.JS_FreeValue(f.context.?, function);
    var resolving_functions = [_]c.JSValue{ c.pi_js_undefined(), c.pi_js_undefined() };
    defer for (resolving_functions) |value| c.JS_FreeValue(f.context.?, value);
    const gate = try f.checked(c.JS_NewPromiseCapability(f.context.?, &resolving_functions));
    defer c.JS_FreeValue(f.context.?, gate);
    var args = [_]c.JSValue{gate};
    const promise = try f.checked(c.JS_Call(f.context.?, function, c.pi_js_undefined(), 1, &args));
    defer c.JS_FreeValue(f.context.?, promise);
    try std.testing.expectEqual(@as(usize, 1), probe.async_starts);
    try std.testing.expectEqual(@as(usize, 0), probe.async_resumes);
    {
        const scope = Scope.enter(&f); defer scope.restore();
        // Native intrinsic settlement may enqueue work; the disallow checkpoint
        // must neither consume that reaction nor settle the waiting invocation.
        const settled = try f.checked(c.JS_PiSettlePromise(f.context.?, gate, c.pi_js_int32(f.context.?, 53), false));
        defer c.JS_FreeValue(f.context.?, settled);
        try std.testing.expect(c.JS_IsJobPending(f.runtime.?));
        var context: ?*c.JSContext = f.context.?;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ExecutePendingJob(f.runtime.?, &context));
        try std.testing.expect(context == null);
        try std.testing.expectEqual(@as(usize, 0), probe.async_resumes);
        try std.testing.expect(c.JS_PromiseState(f.context.?, promise) == c.JS_PROMISE_PENDING);
        c.JS_RunGC(f.runtime.?);
        try std.testing.expect(c.JS_IsJobPending(f.runtime.?));
    }
    try std.testing.expect(try f.drain() > 0);
    try std.testing.expectEqual(@as(usize, 1), probe.async_resumes);
    try std.testing.expect(c.JS_PromiseState(f.context.?, promise) == c.JS_PROMISE_FULFILLED);
    const result = c.JS_PromiseResult(f.context.?, promise); defer c.JS_FreeValue(f.context.?, result);
    try f.numberValue(result, 53);
}

test "VM DisallowJS actual Promise jobs and capability context roots survive blocked checkpoints and GC" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f);
    const token = try probe.holder(&f, 0);
    probe.hook_expected = token; // Borrowed only while actual context/job roots own it.
    c.JS_SetExecutionContext(f.runtime.?, token);
    const promise = try f.eval("globalThis.progress={runs:0};Promise.resolve(1).then(()=>{++progress.runs;})");
    defer c.JS_FreeValue(f.context.?, promise);
    const progress = try f.eval("progress"); defer c.JS_FreeValue(f.context.?, progress);
    c.JS_SetExecutionContext(f.runtime.?, c.pi_js_undefined());
    c.JS_FreeValue(f.context.?, token);
    try std.testing.expectEqual(@as(usize, 0), probe.counts[0]);
    c.JS_SetExecutionContextHook(f.runtime.?, contextHook, &probe);
    {
        const scope = Scope.enter(&f); defer scope.restore();
        for (0..2) |_| {
            var context: ?*c.JSContext = f.context.?;
            try std.testing.expectEqual(@as(c_int, 0), c.JS_ExecutePendingJob(f.runtime.?, &context));
            try std.testing.expect(context == null);
            try std.testing.expect(c.JS_IsJobPending(f.runtime.?));
            try std.testing.expect(!c.JS_HasException(f.context.?));
            c.JS_RunGC(f.runtime.?);
            try std.testing.expectEqual(@as(usize, 0), probe.counts[0]);
        }
        try std.testing.expectEqual(@as(usize, 0), probe.hook_before);
        try std.testing.expectEqual(@as(usize, 0), probe.hook_after);
        try f.ownNumber(progress, "runs", 0);
        try std.testing.expectEqual(@as(usize, 0), try f.drain());
    }
    try std.testing.expectEqual(@as(usize, 1), try f.drain());
    try f.ownNumber(progress, "runs", 1);
    try std.testing.expectEqual(@as(usize, 1), probe.hook_before);
    try std.testing.expectEqual(@as(usize, 1), probe.hook_after);
    try std.testing.expect(!probe.hook_mismatch);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    probe.hook_expected = c.pi_js_undefined();
}

test "VM DisallowJS native jobs remain queued and empty checkpoints retain the zero contract" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f);
    {
        const scope = Scope.enter(&f); defer scope.restore();
        var context: ?*c.JSContext = f.context.?;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ExecutePendingJob(f.runtime.?, &context));
        try std.testing.expect(context == null);
        try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
        const token = try probe.holder(&f, 0);
        var args = [_]c.JSValue{token};
        const status = c.JS_EnqueueJob(f.context.?, nativeJob, 1, &args);
        c.JS_FreeValue(f.context.?, token);
        try std.testing.expectEqual(@as(c_int, 0), status);
        context = f.context.?;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ExecutePendingJob(f.runtime.?, &context));
        try std.testing.expect(context == null);
        try std.testing.expectEqual(@as(usize, 0), probe.job_calls);
        try std.testing.expectEqual(@as(usize, 0), probe.counts[0]);
        try std.testing.expect(c.JS_IsJobPending(f.runtime.?));
    }
    try std.testing.expectEqual(@as(usize, 1), try f.drain());
    try std.testing.expectEqual(@as(usize, 1), probe.job_calls);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
}

test "VM DisallowJS pending call constructor admission and job entries preserve the actual first reason" {
    inline for (.{ false, true }) |uncatchable| {
        var probe: Probe = .{};
        var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f);
        const function = try f.checked(c.JS_NewCFunctionData(f.context.?, nativeReturn, 0, 0, 0, null));
        defer c.JS_FreeValue(f.context.?, function);
        const reason = try f.checked(c.JS_NewError(f.context.?)); defer c.JS_FreeValue(f.context.?, reason);
        if (uncatchable) c.JS_SetUncatchableError(f.context.?, reason);
        try std.testing.expectEqual(@as(c_int, 0), c.JS_EnqueueJob(f.context.?, nativeJob, 0, null));
        {
            const scope = Scope.enter(&f); defer scope.restore();
            // All operations share the same retained pending owner. In
            // particular, invalid call/constructor brands must not replace it.
            _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, reason));
            try std.testing.expect(c.JS_IsException(c.JS_Call(f.context.?, c.pi_js_null(), c.pi_js_undefined(), 0, null)));
            try std.testing.expect(c.JS_IsException(c.JS_CallConstructor(f.context.?, c.pi_js_null(), 0, null)));
            try std.testing.expectEqual(@as(c_int, -1), c.JS_PiMarkNativeApiFunction(f.context.?, function));
            var context: ?*c.JSContext = null;
            try std.testing.expectEqual(@as(c_int, -1), c.JS_ExecutePendingJob(f.runtime.?, &context));
            try std.testing.expect(context == f.context.?);
            const observed = try f.pendingReason(); defer c.JS_FreeValue(f.context.?, observed);
            try std.testing.expect(c.JS_IsStrictEqual(f.context.?, reason, observed));
            try std.testing.expect(c.JS_IsUncatchableError(observed) == uncatchable);
            try std.testing.expectEqual(@as(usize, 0), probe.job_calls);
            try std.testing.expect(c.JS_IsJobPending(f.runtime.?));
            // Failed admission did not silently mark the previously ordinary
            // native Source function once the prior pending reason was taken.
            const blocked = try f.exception(f.call(function)); defer c.JS_FreeValue(f.context.?, blocked);
            try f.illegal(blocked); try std.testing.expectEqual(@as(usize, 0), probe.calls);
        }
        try std.testing.expectEqual(@as(usize, 1), try f.drain());
    }
}

test "VM DisallowJS allowed native fatal preempts a later blocked entry and guest catch or finally" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f);
    const reason = try f.checked(c.JS_NewError(f.context.?)); defer c.JS_FreeValue(f.context.?, reason);
    c.JS_SetUncatchableError(f.context.?, reason);
    const nested = try f.eval("globalThis.progress={body:false,caught:false,finally:false,after:false};(function(){progress.body=true;})");
    defer c.JS_FreeValue(f.context.?, nested);
    const progress = try f.eval("progress"); defer c.JS_FreeValue(f.context.?, progress);
    const fatal = try f.api(nativeFatalThenCall, "ActualFatalAPI", &.{ reason, nested });
    defer c.JS_FreeValue(f.context.?, fatal);
    const scope_call = try f.api(nativeScopeCall, "ActualScopeAPI", &.{});
    defer c.JS_FreeValue(f.context.?, scope_call);
    try f.set("actualFatal", fatal); try f.set("actualScope", scope_call);
    const observed = try f.exception(f.evalRaw(
        \\try{actualScope(actualFatal);progress.after=true;}
        \\catch(reason){progress.caught=true;throw reason;}
        \\finally{progress.finally=true;}
    )); defer c.JS_FreeValue(f.context.?, observed);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, reason, observed));
    try std.testing.expect(c.JS_IsUncatchableError(observed));
    try std.testing.expectEqual(@as(usize, 1), probe.calls);
    try f.ownBool(progress, "body", false); try f.ownBool(progress, "caught", false);
    try f.ownBool(progress, "finally", false); try f.ownBool(progress, "after", false);
    // Only a host Boolean exchange is used to observe restored scope state.
    const was_allowed = c.JS_PiExchangeJavascriptExecutionAllowed(f.runtime.?, true);
    try std.testing.expect(was_allowed);
}

test "VM DisallowJS ordinary illegal access is catchable after exact native scope restoration" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f);
    const scope_call = try f.api(nativeScopeCall, "ActualScopeAPI", &.{});
    defer c.JS_FreeValue(f.context.?, scope_call); try f.set("actualScope", scope_call);
    const progress = try f.eval(
        \\globalThis.progress={body:false,caught:false,finally:false,after:false,reason:null};
        \\globalThis.subject=function(){progress.body=true;};
        \\progress
    ); defer c.JS_FreeValue(f.context.?, progress);
    try f.run(
        \\try{actualScope(subject);progress.after=true;}
        \\catch(reason){progress.caught=true;progress.reason=reason;}
        \\finally{progress.finally=true;}
    );
    try f.ownBool(progress, "body", false); try f.ownBool(progress, "caught", true);
    try f.ownBool(progress, "finally", true); try f.ownBool(progress, "after", false);
    const reason = try f.checked(c.JS_GetPropertyStr(f.context.?, progress, "reason"));
    defer c.JS_FreeValue(f.context.?, reason); try f.illegal(reason);
    try std.testing.expect(c.JS_PiExchangeJavascriptExecutionAllowed(f.runtime.?, true));
}

test "VM DisallowJS blocked entries borrow callable receiver and arguments without retiring or retaining them" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f);
    var function = try f.eval("(function(value){return value;})");
    defer c.JS_FreeValue(f.context.?, function);
    try probe.attach(&f, function, 0);
    var receiver = try probe.holder(&f, 1); defer c.JS_FreeValue(f.context.?, receiver);
    var argument = try probe.holder(&f, 2); defer c.JS_FreeValue(f.context.?, argument);
    {
        const scope = Scope.enter(&f); defer scope.restore();
        var args = [_]c.JSValue{argument};
        const reason = try f.exception(c.JS_Call(f.context.?, function, receiver, 1, &args));
        defer c.JS_FreeValue(f.context.?, reason); try f.illegal(reason);
        c.JS_RunGC(f.runtime.?);
        try std.testing.expectEqual([3]usize{ 0, 0, 0 }, probe.counts);
    }
    c.JS_FreeValue(f.context.?, argument); argument = c.pi_js_undefined();
    c.JS_FreeValue(f.context.?, receiver); receiver = c.pi_js_undefined();
    c.JS_FreeValue(f.context.?, function); function = c.pi_js_undefined();
    try std.testing.expectEqual([3]usize{ 1, 1, 1 }, probe.counts);
    c.JS_RunGC(f.runtime.?);
    try std.testing.expectEqual([3]usize{ 1, 1, 1 }, probe.counts);
}

test "VM DisallowJS actual generator and async generator continuations stay unentered until restoration" {
    inline for (.{ false, true }) |is_async| {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        const iterator = try f.eval(if (is_async)
            "globalThis.progress={body:false};(async function*(){progress.body=true;yield 67;})()"
        else
            "globalThis.progress={body:false};(function*(){progress.body=true;yield 67;})()");
        defer c.JS_FreeValue(f.context.?, iterator);
        const next = try f.checked(c.JS_GetPropertyStr(f.context.?, iterator, "next"));
        defer c.JS_FreeValue(f.context.?, next);
        const progress = try f.eval("progress"); defer c.JS_FreeValue(f.context.?, progress);
        {
            const scope = Scope.enter(&f); defer scope.restore();
            const reason = try f.exception(c.JS_Call(f.context.?, next, iterator, 0, null));
            defer c.JS_FreeValue(f.context.?, reason); try f.illegal(reason);
            try f.ownBool(progress, "body", false);
            try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
        }
        const returned = try f.checked(c.JS_Call(f.context.?, next, iterator, 0, null));
        defer c.JS_FreeValue(f.context.?, returned);
        const result = if (is_async) blk: {
            _ = try f.drain();
            try std.testing.expect(c.JS_PromiseState(f.context.?, returned) == c.JS_PROMISE_FULFILLED);
            break :blk c.JS_PromiseResult(f.context.?, returned);
        } else c.JS_DupValue(f.context.?, returned);
        defer c.JS_FreeValue(f.context.?, result);
        try f.ownNumber(result, "value", 67); try f.ownBool(result, "done", false);
        try f.ownBool(progress, "body", true);
    }
}

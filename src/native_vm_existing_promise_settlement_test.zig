//! Controls for direct settlement of an existing intrinsic Promise. The programs
//! use the linked VM and its real reaction queue. Native entry pending policy is
//! tested separately from ordinary rejection DATA; no Node/V8 execution is
//! claimed by this source-only control unit.
const std = @import("std");
const c = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("engine_abi.h");
});
const memory_limit: usize = 64 * 1024 * 1024;
const Fixture = struct {
    runtime: ?*c.JSRuntime = null,
    context: ?*c.JSContext = null,
    memory: ?*anyopaque = null,
    fn init(self: *Fixture) !void {
        self.* = .{};
        self.runtime = c.pi_js_new_runtime(memory_limit, &self.memory) orelse return error.OutOfMemory;
        errdefer self.deinit();
        self.context = c.JS_NewContext(self.runtime.?) orelse return error.OutOfMemory;
    }
    fn deinit(self: *Fixture) void {
        if (self.context) |context| { self.context = null; c.JS_FreeContext(context); }
        if (self.runtime) |runtime| { self.runtime = null; c.JS_FreeRuntime(runtime); }
        if (self.memory) |memory| { self.memory = null; c.pi_js_release_memory_owner(memory); }
    }
    fn checked(self: *Fixture, value: c.JSValue) !c.JSValue {
        if (c.JS_IsException(value) or c.JS_HasException(self.context.?)) {
            if (!c.JS_IsException(value)) c.JS_FreeValue(self.context.?, value);
            const reason = c.JS_GetException(self.context.?);
            c.JS_FreeValue(self.context.?, reason);
            return error.ActualPromiseSettlementControlException;
        }
        return value;
    }
    fn evalRaw(self: *Fixture, source: [:0]const u8) c.JSValue {
        return c.JS_Eval(self.context.?, source.ptr, source.len,
            "actual-existing-promise-control.js", c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_STRICT);
    }
    fn eval(self: *Fixture, source: [:0]const u8) !c.JSValue {
        return self.checked(self.evalRaw(source));
    }
    fn run(self: *Fixture, source: [:0]const u8) !void {
        const result = try self.eval(source); defer c.JS_FreeValue(self.context.?, result);
    }
    fn set(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        const global = try self.checked(c.JS_GetGlobalObject(self.context.?));
        defer c.JS_FreeValue(self.context.?, global);
        const result = c.JS_SetPropertyStr(self.context.?, global, name, c.JS_DupValue(self.context.?, value));
        if (result < 0 or c.JS_HasException(self.context.?)) {
            const reason = c.JS_GetException(self.context.?); c.JS_FreeValue(self.context.?, reason);
            return error.ActualPromiseSettlementControlPropertyFailure;
        }
    }
    fn pending(self: *Fixture) !c.JSValue {
        var functions = [_]c.JSValue{ c.pi_js_undefined(), c.pi_js_undefined() };
        defer for (functions) |function| c.JS_FreeValue(self.context.?, function);
        return self.checked(c.JS_NewPromiseCapability(self.context.?, &functions));
    }
    fn settle(self: *Fixture, promise: c.JSValue, value: c.JSValue, reject: bool) !void {
        const result = try self.checked(c.JS_PiSettlePromise(self.context.?, promise, value, reject));
        defer c.JS_FreeValue(self.context.?, result);
        try std.testing.expect(c.JS_IsUndefined(result));
    }
    fn exception(self: *Fixture, result: c.JSValue) !c.JSValue {
        try std.testing.expect(c.JS_IsException(result));
        try std.testing.expect(c.JS_HasException(self.context.?));
        return c.JS_GetException(self.context.?);
    }
    fn number(self: *Fixture, source: [:0]const u8) !i32 {
        const result = try self.eval(source); defer c.JS_FreeValue(self.context.?, result);
        try std.testing.expect(c.JS_IsNumber(result));
        var value: i32 = 0;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(self.context.?, &value, result));
        return value;
    }
    fn resultNumber(self: *Fixture, promise: c.JSValue, expected: i32) !void {
        const result = c.JS_PromiseResult(self.context.?, promise); defer c.JS_FreeValue(self.context.?, result);
        try std.testing.expect(c.JS_IsNumber(result));
        var value: i32 = 0;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(self.context.?, &value, result));
        try std.testing.expectEqual(expected, value);
    }
    fn resultIdentity(self: *Fixture, promise: c.JSValue, expected: c.JSValue) !void {
        const result = c.JS_PromiseResult(self.context.?, promise); defer c.JS_FreeValue(self.context.?, result);
        try std.testing.expect(c.JS_IsStrictEqual(self.context.?, expected, result));
    }
    fn ownFalse(self: *Fixture, record: c.JSValue, key: [*:0]const u8) !void {
        // The record is retained before failure and contains only these own data
        // fields. This observation does not invoke a guest progress callback.
        const value = c.JS_GetPropertyStr(self.context.?, record, key);
        defer c.JS_FreeValue(self.context.?, value);
        try std.testing.expect(c.JS_IsBool(value));
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToBool(self.context.?, value));
    }
    fn ownNumber(self: *Fixture, record: c.JSValue, key: [*:0]const u8, expected: i32) !void {
        const value = c.JS_GetPropertyStr(self.context.?, record, key);
        defer c.JS_FreeValue(self.context.?, value);
        try std.testing.expect(c.JS_IsNumber(value));
        var number_value: i32 = 0;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(self.context.?, &number_value, value));
        try std.testing.expectEqual(expected, number_value);
    }
    fn drain(self: *Fixture) !usize {
        var count: usize = 0;
        while (c.JS_IsJobPending(self.runtime.?)) {
            if (count == 64) return error.ActualPromiseSettlementControlJobBudget;
            var context: ?*c.JSContext = null;
            const status = c.JS_ExecutePendingJob(self.runtime.?, &context);
            if (status < 0 or c.JS_HasException(context orelse self.context.?)) {
                const reason = c.JS_GetException(context orelse self.context.?);
                c.JS_FreeValue(context orelse self.context.?, reason);
                return error.ActualPromiseSettlementControlJobException;
            }
            try std.testing.expectEqual(@as(c_int, 1), status);
            count += 1;
        }
        c.JS_ClearKeptObjects(self.runtime.?);
        return count;
    }
};
const Capability = struct {
    promise: c.JSValue,
    functions: [2]c.JSValue,
    fn init(f: *Fixture) !Capability {
        var functions = [_]c.JSValue{ c.pi_js_undefined(), c.pi_js_undefined() };
        errdefer for (functions) |function| c.JS_FreeValue(f.context.?, function);
        const promise = try f.checked(c.JS_NewPromiseCapability(f.context.?, &functions));
        return .{ .promise = promise, .functions = functions };
    }
    fn deinit(self: *Capability, f: *Fixture) void {
        for (self.functions) |function| c.JS_FreeValue(f.context.?, function);
        c.JS_FreeValue(f.context.?, self.promise);
    }
    fn call(self: *Capability, f: *Fixture, reject: bool, input: c.JSValue) !void {
        var args = [_]c.JSValue{input};
        const result = try f.checked(c.JS_Call(f.context.?, self.functions[@intFromBool(reject)],
            c.pi_js_undefined(), 1, &args));
        defer c.JS_FreeValue(f.context.?, result);
        try std.testing.expect(c.JS_IsUndefined(result));
    }
};

test "VM Promise settlement uses the same existing intrinsic Promise and borrowed result" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run(
        \\globalThis.factoryGets=0;
        \\Object.defineProperty(globalThis,"Promise",{configurable:true,get(){++factoryGets;throw Error("public Promise");}});
    );
    const fulfilled = try f.pending(); defer c.JS_FreeValue(f.context.?, fulfilled);
    const rejected = try f.pending(); defer c.JS_FreeValue(f.context.?, rejected);
    const reason = try f.eval("({privateReason:1})"); defer c.JS_FreeValue(f.context.?, reason);
    const identity = c.pi_js_object_identity(fulfilled);
    try f.settle(fulfilled, c.pi_js_int32(f.context.?, 23), false);
    try f.settle(rejected, reason, true);
    try std.testing.expect(identity == c.pi_js_object_identity(fulfilled));
    try std.testing.expect(c.JS_PromiseState(f.context.?, fulfilled) == c.JS_PROMISE_FULFILLED);
    try std.testing.expect(c.JS_PromiseState(f.context.?, rejected) == c.JS_PROMISE_REJECTED);
    try f.resultNumber(fulfilled, 23);
    try f.resultIdentity(rejected, reason);
    try std.testing.expectEqual(@as(i32, 0), try f.number("factoryGets"));
    try std.testing.expect(!c.JS_HasException(f.context.?));
    try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
}

test "VM Promise settlement settled guard observes no value under a failing allocation limit" {
    inline for (.{ false, true }) |reject| {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        const promise = try f.pending(); defer c.JS_FreeValue(f.context.?, promise);
        const poison = try f.eval(
            \\globalThis.gets=0;({get then(){++gets;throw Error("late then");}})
        ); defer c.JS_FreeValue(f.context.?, poison);
        try f.settle(promise, c.pi_js_int32(f.context.?, 41), reject);
        {
            // Zero means unlimited in this VM. One makes the positive-allocation
            // ceiling zero while leaving all pre-existing objects available.
            c.JS_SetMemoryLimit(f.runtime.?, 1);
            defer c.JS_SetMemoryLimit(f.runtime.?, 0);
            try f.settle(promise, poison, false);
            try f.settle(promise, poison, true);
        }
        try f.resultNumber(promise, 41);
        try std.testing.expect(c.JS_PromiseState(f.context.?, promise) ==
            (if (reject) c.JS_PROMISE_REJECTED else c.JS_PROMISE_FULFILLED));
        try std.testing.expectEqual(@as(i32, 0), try f.number("gets"));
        try std.testing.expect(!c.JS_HasException(f.context.?));
    }
}

test "VM Promise settlement primitive resolution creates no new resolver allocation" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const promise = try f.pending(); defer c.JS_FreeValue(f.context.?, promise);
    {
        c.JS_SetMemoryLimit(f.runtime.?, 1);
        defer c.JS_SetMemoryLimit(f.runtime.?, 0);
        try f.settle(promise, c.pi_js_int32(f.context.?, 17), false);
    }
    try std.testing.expect(c.JS_PromiseState(f.context.?, promise) == c.JS_PROMISE_FULFILLED);
    try f.resultNumber(promise, 17);
    try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
}

test "VM Promise settlement gets then synchronously and invokes it through the actual queued job" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const promise = try f.pending(); defer c.JS_FreeValue(f.context.?, promise);
    const value = try f.eval(
        \\globalThis.trace=[];globalThis.payload={answer:1};
        \\globalThis.input={get then(){trace.push("get");return function(resolve,reject){
        \\ trace.push(this===input?"this":"wrong");trace.push(typeof resolve,typeof reject);resolve(payload);
        \\};}};input
    ); defer c.JS_FreeValue(f.context.?, value);
    const payload = try f.eval("payload"); defer c.JS_FreeValue(f.context.?, payload);
    try f.settle(promise, value, false);
    try f.run("if(trace.join(',')!=='get')throw Error('then called synchronously');");
    try std.testing.expect(c.JS_PromiseState(f.context.?, promise) == c.JS_PROMISE_PENDING);
    try std.testing.expectEqual(@as(usize, 1), try f.drain());
    try f.run("if(trace.join(',')!=='get,this,function,function')throw Error('actual then job');");
    try f.resultIdentity(promise, payload);
}

test "VM Promise settlement uses a genuine input Promise live then override" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const promise = try f.pending(); defer c.JS_FreeValue(f.context.?, promise);
    const value = try f.eval(
        \\globalThis.gets=0;globalThis.calls=0;globalThis.input=Promise.resolve(3);
        \\Object.defineProperty(input,"then",{get(){++gets;return function(resolve){
        \\ if(this!==input)throw Error("Promise receiver");++calls;resolve(89);
        \\};}});input
    ); defer c.JS_FreeValue(f.context.?, value);
    try std.testing.expect(c.JS_IsPromise(value));
    try f.settle(promise, value, false);
    try std.testing.expectEqual(@as(i32, 1), try f.number("gets"));
    try std.testing.expectEqual(@as(i32, 0), try f.number("calls"));
    try std.testing.expectEqual(@as(usize, 1), try f.drain());
    try std.testing.expectEqual(@as(i32, 1), try f.number("calls"));
    try f.resultNumber(promise, 89);
}

test "VM Promise settlement repeated native calls during adoption differ from the settled guard" {
    inline for (.{ false, true }) |reject| {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        const promise = try f.pending(); defer c.JS_FreeValue(f.context.?, promise);
        const value = try f.eval(
            \\globalThis.gets=0;globalThis.calls=0;
            \\({get then(){++gets;return function(resolve){++calls;resolve(900);};}})
        ); defer c.JS_FreeValue(f.context.?, value);
        try f.settle(promise, value, false);
        try f.settle(promise, value, false);
        try std.testing.expect(c.JS_PromiseState(f.context.?, promise) == c.JS_PROMISE_PENDING);
        try std.testing.expectEqual(@as(i32, 2), try f.number("gets"));
        try f.settle(promise, c.pi_js_int32(f.context.?, 73), reject);
        try f.settle(promise, value, false);
        try std.testing.expectEqual(@as(i32, 2), try f.number("gets"));
        try std.testing.expectEqual(@as(usize, 2), try f.drain());
        try std.testing.expectEqual(@as(i32, 2), try f.number("calls"));
        try std.testing.expect(c.JS_PromiseState(f.context.?, promise) ==
            (if (reject) c.JS_PROMISE_REJECTED else c.JS_PROMISE_FULFILLED));
        try f.resultNumber(promise, 73);
    }
}

test "VM Promise settlement extraction preserves original resolving function one-shot latch" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var capability = try Capability.init(&f); defer capability.deinit(&f);
    const first = try f.eval(
        \\globalThis.firstGets=0;globalThis.secondGets=0;
        \\({get then(){++firstGets;return function(resolve){resolve(11);};}})
    ); defer c.JS_FreeValue(f.context.?, first);
    const second = try f.eval("({get then(){++secondGets;throw Error('second resolve');}})");
    defer c.JS_FreeValue(f.context.?, second);
    try capability.call(&f, false, first);
    try capability.call(&f, false, second);
    try capability.call(&f, true, c.pi_js_int32(f.context.?, 99));
    try std.testing.expect(c.JS_PromiseState(f.context.?, capability.promise) == c.JS_PROMISE_PENDING);
    try std.testing.expectEqual(@as(i32, 1), try f.number("firstGets"));
    try std.testing.expectEqual(@as(i32, 0), try f.number("secondGets"));
    try std.testing.expectEqual(@as(usize, 1), try f.drain());
    try f.resultNumber(capability.promise, 11);
}

test "VM Promise settlement self resolution rejects the same Promise with actual TypeError" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const promise = try f.pending(); defer c.JS_FreeValue(f.context.?, promise);
    try f.settle(promise, promise, false);
    try std.testing.expect(c.JS_PromiseState(f.context.?, promise) == c.JS_PROMISE_REJECTED);
    const reason = c.JS_PromiseResult(f.context.?, promise); defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(c.JS_IsError(reason));
    try f.set("reason", reason);
    try f.run("if(!(reason instanceof TypeError)||reason.message!=='promise self resolution')throw Error('self reason');");
    try std.testing.expect(!c.JS_HasException(f.context.?));
    try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
}

test "VM Promise settlement ordinary then getter throw rejects while noncallable then fulfills" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const rejected = try f.pending(); defer c.JS_FreeValue(f.context.?, rejected);
    const fulfilled = try f.pending(); defer c.JS_FreeValue(f.context.?, fulfilled);
    const reason = try f.eval("globalThis.reason={privateReason:7};reason");
    defer c.JS_FreeValue(f.context.?, reason);
    const throwing = try f.eval("globalThis.gets=0;({get then(){++gets;throw reason;}})");
    defer c.JS_FreeValue(f.context.?, throwing);
    const plain = try f.eval("({get then(){++gets;return 12;}})"); defer c.JS_FreeValue(f.context.?, plain);
    try f.settle(rejected, throwing, false);
    try f.settle(fulfilled, plain, false);
    try std.testing.expect(c.JS_PromiseState(f.context.?, rejected) == c.JS_PROMISE_REJECTED);
    try std.testing.expect(c.JS_PromiseState(f.context.?, fulfilled) == c.JS_PROMISE_FULFILLED);
    try f.resultIdentity(rejected, reason);
    try f.resultIdentity(fulfilled, plain);
    try std.testing.expectEqual(@as(i32, 2), try f.number("gets"));
    try std.testing.expect(!c.JS_HasException(f.context.?));
    try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
}

test "VM Promise settlement returned flagged Error DATA remains a normal value or rejection" {
    inline for (.{ false, true }) |reject| {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        const promise = try f.pending(); defer c.JS_FreeValue(f.context.?, promise);
        const reason = try f.checked(c.JS_NewError(f.context.?)); defer c.JS_FreeValue(f.context.?, reason);
        c.JS_SetUncatchableError(f.context.?, reason);
        try std.testing.expect(!c.JS_HasException(f.context.?));
        try f.settle(promise, reason, reject);
        try std.testing.expect(c.JS_PromiseState(f.context.?, promise) ==
            (if (reject) c.JS_PROMISE_REJECTED else c.JS_PROMISE_FULFILLED));
        try f.resultIdentity(promise, reason);
        try std.testing.expect(c.JS_IsUncatchableError(reason));
        try std.testing.expect(!c.JS_HasException(f.context.?));
    }
}

test "VM Promise settlement accepts a genuine foreign realm Promise and rejects proxy brands intrinsically" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const foreign = c.JS_NewContext(f.runtime.?) orelse return error.OutOfMemory;
    defer c.JS_FreeContext(foreign);
    var functions = [_]c.JSValue{ c.pi_js_undefined(), c.pi_js_undefined() };
    defer for (functions) |function| c.JS_FreeValue(foreign, function);
    const promise = try f.checked(c.JS_NewPromiseCapability(foreign, &functions));
    defer c.JS_FreeValue(foreign, promise);
    try f.settle(promise, c.pi_js_int32(f.context.?, 67), false);
    try std.testing.expect(c.JS_PromiseState(foreign, promise) == c.JS_PROMISE_FULFILLED);
    try f.resultNumber(promise, 67);
    try f.set("foreignPromise", promise);
    const proxy = try f.eval(
        \\globalThis.traps=0;new Proxy(foreignPromise,{get(){++traps;throw Error("proxy brand get");},
        \\ getPrototypeOf(){++traps;throw Error("proxy brand prototype");}})
    ); defer c.JS_FreeValue(f.context.?, proxy);
    const reason = try f.exception(c.JS_PiSettlePromise(f.context.?, proxy, promise, false));
    defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(c.JS_IsError(reason));
    try std.testing.expectEqual(@as(i32, 0), try f.number("traps"));
    const primitive_reason = try f.exception(c.JS_PiSettlePromise(f.context.?, c.pi_js_null(), promise, true));
    defer c.JS_FreeValue(f.context.?, primitive_reason);
    try std.testing.expect(c.JS_IsError(primitive_reason));
    try f.resultNumber(promise, 67);
}

test "VM Promise settlement prior pending entry wins before brand and then with borrowed inputs intact" {
    inline for (.{ false, true }) |uncatchable| {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        const promise = try f.pending(); defer c.JS_FreeValue(f.context.?, promise);
        const input = try f.eval("globalThis.gets=0;({get then(){++gets;throw Error('pending then');}})");
        defer c.JS_FreeValue(f.context.?, input);
        const reason = try f.checked(c.JS_NewError(f.context.?)); defer c.JS_FreeValue(f.context.?, reason);
        if (uncatchable) c.JS_SetUncatchableError(f.context.?, reason);
        inline for (.{ false, true }) |invalid| {
            _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, reason));
            c.JS_SetMemoryLimit(f.runtime.?, 1);
            const result = c.JS_PiSettlePromise(f.context.?, if (invalid) c.pi_js_null() else promise, input, false);
            c.JS_SetMemoryLimit(f.runtime.?, 0);
            const observed = try f.exception(result); defer c.JS_FreeValue(f.context.?, observed);
            try std.testing.expect(c.JS_IsStrictEqual(f.context.?, reason, observed));
            try std.testing.expect(c.JS_IsUncatchableError(observed) == uncatchable);
        }
        try std.testing.expect(c.JS_PromiseState(f.context.?, promise) == c.JS_PROMISE_PENDING);
        try std.testing.expectEqual(@as(i32, 0), try f.number("gets"));
        try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
    }
}

fn settleCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue,
    _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const ctx = context orelse return c.pi_js_exception();
    if (argc < 2) return c.JS_ThrowTypeError(ctx, "actual settlement control needs two operands");
    return c.JS_PiSettlePromise(ctx, argv[0], argv[1], false);
}
fn raiseCallback(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue,
    _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const ctx = context orelse return c.pi_js_exception();
    return c.JS_Throw(ctx, c.JS_DupValue(ctx, data[0]));
}
test "VM Promise settlement actual uncatchable then getter escapes without guest catch or later work" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const promise = try f.pending(); defer c.JS_FreeValue(f.context.?, promise);
    const reason = try f.checked(c.JS_NewError(f.context.?)); defer c.JS_FreeValue(f.context.?, reason);
    c.JS_SetUncatchableError(f.context.?, reason);
    var data = [_]c.JSValue{reason};
    const raiser = try f.checked(c.JS_NewCFunctionData(f.context.?, raiseCallback, 0, 0, 1, &data));
    defer c.JS_FreeValue(f.context.?, raiser);
    const settle_function = try f.checked(c.JS_NewCFunctionData(f.context.?, settleCallback, 2, 0, 0, null));
    defer c.JS_FreeValue(f.context.?, settle_function);
    try f.set("vmRaise", raiser); try f.set("vmSettle", settle_function); try f.set("pending", promise);
    try f.run(
        \\globalThis.progress={caught:false,after:false,getAfter:false,gets:0};
        \\globalThis.input={get then(){++progress.gets;vmRaise();progress.getAfter=true;return undefined;}};
    );
    const progress = try f.eval("progress"); defer c.JS_FreeValue(f.context.?, progress);
    const observed = try f.exception(f.evalRaw(
        \\try{vmSettle(pending,input);progress.after=true;}
        \\catch(reason){progress.caught=true;throw reason;}
    )); defer c.JS_FreeValue(f.context.?, observed);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, reason, observed));
    try std.testing.expect(c.JS_IsUncatchableError(observed));
    try f.ownFalse(progress, "caught"); try f.ownFalse(progress, "after"); try f.ownFalse(progress, "getAfter");
    try f.ownNumber(progress, "gets", 1);
    try std.testing.expect(c.JS_PromiseState(f.context.?, promise) == c.JS_PROMISE_PENDING);
    try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
}

test "VM Promise settlement actual thenable job allocation failure leaves pending and permits retry" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const promise = try f.pending(); defer c.JS_FreeValue(f.context.?, promise);
    const input = try f.eval("({then:function(resolve){resolve(17);}})");
    defer c.JS_FreeValue(f.context.?, input);
    c.JS_SetMemoryLimit(f.runtime.?, 1);
    const result = c.JS_PiSettlePromise(f.context.?, promise, input, false);
    c.JS_SetMemoryLimit(f.runtime.?, 0);
    const reason = try f.exception(result); defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(c.JS_IsNull(reason));
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.JS_PromiseState(f.context.?, promise) == c.JS_PROMISE_PENDING);
    try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
    try f.settle(promise, input, false);
    try std.testing.expectEqual(@as(usize, 1), try f.drain());
    try f.resultNumber(promise, 17);
}

test "VM Promise settlement reaction allocation failure preserves already published state and current error" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const promise = try f.pending(); defer c.JS_FreeValue(f.context.?, promise);
    try f.set("pending", promise);
    const next = try f.eval(
        \\globalThis.visits=0;pending.then(function(){++visits;})
    ); defer c.JS_FreeValue(f.context.?, next);
    c.JS_SetMemoryLimit(f.runtime.?, 1);
    const result = c.JS_PiSettlePromise(f.context.?, promise, c.pi_js_int32(f.context.?, 29), false);
    c.JS_SetMemoryLimit(f.runtime.?, 0);
    const reason = try f.exception(result); defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(c.JS_IsNull(reason));
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.JS_PromiseState(f.context.?, promise) == c.JS_PROMISE_FULFILLED);
    try std.testing.expect(c.JS_PromiseState(f.context.?, next) == c.JS_PROMISE_PENDING);
    try f.resultNumber(promise, 29);
    try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
    try std.testing.expectEqual(@as(i32, 0), try f.number("visits"));
    try f.settle(promise, c.pi_js_int32(f.context.?, 31), true);
    try f.resultNumber(promise, 29);
}

const Token = struct { probe: *Probe, index: usize };
const Probe = struct {
    counts: [2]usize = .{ 0, 0 },
    tokens: [2]Token = undefined,
    class_id: c.JSClassID = 0,
    fn init(self: *Probe, f: *Fixture) !void {
        self.tokens = .{ .{ .probe = self, .index = 0 }, .{ .probe = self, .index = 1 } };
        _ = c.JS_NewClassID(f.runtime.?, &self.class_id);
        const definition: c.JSClassDef = .{ .class_name = "Actual Promise operand holder", .finalizer = retire };
        try std.testing.expectEqual(@as(c_int, 0), c.JS_NewClass(f.runtime.?, self.class_id, &definition));
    }
    fn retire(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
        const raw = c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return;
        const token: *Token = @ptrCast(@alignCast(raw));
        _ = c.JS_SetOpaque(value, null);
        token.probe.counts[token.index] += 1;
    }
    fn attach(self: *Probe, f: *Fixture, target: c.JSValue, index: usize) !void {
        const marker = try f.checked(c.JS_NewObjectClass(f.context.?, self.class_id));
        defer c.JS_FreeValue(f.context.?, marker);
        _ = c.JS_SetOpaque(marker, &self.tokens[index]);
        try std.testing.expectEqual(@as(c_int, 1), c.JS_DefinePropertyValueStr(f.context.?, target,
            "actualOwnerMarker", c.JS_DupValue(f.context.?, marker), c.JS_PROP_C_W_E));
    }
    fn expectCounts(self: *Probe, expected: [2]usize) !void {
        try std.testing.expectEqualSlices(usize, &expected, &self.counts);
    }
};
test "VM Promise settlement borrows resolution and selected method through caller-owned retirement" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try probe.init(&f);
    const promise = try f.pending(); defer c.JS_FreeValue(f.context.?, promise);
    var input = try f.eval("({then:function(resolve){resolve(71);}})");
    defer c.JS_FreeValue(f.context.?, input);
    var method = try f.checked(c.JS_GetPropertyStr(f.context.?, input, "then"));
    defer c.JS_FreeValue(f.context.?, method);
    try probe.attach(&f, input, 0); try probe.attach(&f, method, 1);
    try f.settle(promise, input, false);
    try std.testing.expectEqual(@as(usize, 1), try f.drain());
    try probe.expectCounts(.{ 0, 0 });
    try f.resultNumber(promise, 71);
    c.JS_FreeValue(f.context.?, method); method = c.pi_js_undefined();
    c.JS_FreeValue(f.context.?, input); input = c.pi_js_undefined();
    try probe.expectCounts(.{ 1, 1 });
    c.JS_RunGC(f.runtime.?);
    try probe.expectCounts(.{ 1, 1 });
}

test "VM Promise settlement actual queued job retains operands across caller release and live GC" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try probe.init(&f);
    const promise = try f.pending(); defer c.JS_FreeValue(f.context.?, promise);
    var input = try f.eval("({then:function(resolve){resolve(97);}})");
    defer c.JS_FreeValue(f.context.?, input);
    var method = try f.checked(c.JS_GetPropertyStr(f.context.?, input, "then"));
    defer c.JS_FreeValue(f.context.?, method);
    try probe.attach(&f, input, 0); try probe.attach(&f, method, 1);
    try f.settle(promise, input, false);
    c.JS_FreeValue(f.context.?, method); method = c.pi_js_undefined();
    c.JS_FreeValue(f.context.?, input); input = c.pi_js_undefined();
    c.JS_RunGC(f.runtime.?);
    try probe.expectCounts(.{ 0, 0 });
    try std.testing.expect(c.JS_PromiseState(f.context.?, promise) == c.JS_PROMISE_PENDING);
    try std.testing.expectEqual(@as(usize, 1), try f.drain());
    try probe.expectCounts(.{ 1, 1 });
    try f.resultNumber(promise, 97);
    c.JS_RunGC(f.runtime.?);
    try probe.expectCounts(.{ 1, 1 });
}

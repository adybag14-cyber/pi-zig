//! Source-only successor controls; exact5d25 is preserved as a negative.
const std = @import("std");
const x = @import("extensions/native_ai_auth_helper_values.zig");
const subject = @import("extensions/native_ai_auth_helpers.zig");
const c = x.c;
fn put(engine: *x.em.Engine, name: [*:0]const u8, value: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try @import("extensions/native_js_values.zig").define(engine, global, name, c.JS_DupValue(engine.context, value));
}
fn rawPut(engine: *x.em.Engine, name: [*:0]const u8, value: c.JSValue) void {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    _ = c.JS_DefinePropertyValueStr(engine.context, global, name, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E);
}
fn privateData(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = x.em.Engine.fromContext(context.?); _ = engine.throwNativeOutOfMemory();
    return c.JS_GetException(context); // Successful unmarked private DATA A.
}
fn fatalB(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = x.em.Engine.fromContext(context.?);
    _ = engine.checked(engine.throwNativeOutOfMemoryFatal()) catch {};
    rawPut(engine, "actualB", engine.captured_exception.?);
    // No VM pending remains. Only the ACTUAL active invocation retains B1.
    return c.pi_js_undefined();
}
fn capturedData(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = x.em.Engine.fromContext(context.?); const data = privateData(context, c.pi_js_undefined(), 0, null);
    defer engine.freeValue(data);
    c.JS_SetUncatchableError(context, data);
    var resolving: [2]c.JSValue = undefined;
    const promise = c.JS_NewPromiseCapability(context, &resolving);
    if (c.JS_IsException(promise)) return promise;
    defer engine.freeValue(promise); defer engine.freeValue(resolving[0]); defer engine.freeValue(resolving[1]);
    var arguments = [_]c.JSValue{data};
    const rejected = c.JS_Call(context, resolving[1], c.pi_js_undefined(), 1, &arguments);
    if (c.JS_IsException(rejected)) return rejected;
    engine.freeValue(rejected);
    // Actual PromiseResult DATA is captured by the real Engine path. No slot
    // assignment, actual pending producer, private-tag policy or B1 is forged.
    if (engine.awaitValueOnly(promise)) |value| {
        engine.freeValue(value); return c.JS_ThrowInternalError(context, "Expected rejected Promise DATA");
    } else |err| if (err != error.JavaScriptException) return @import("extensions/native_sdk.zig").fail(engine, err);
    return c.JS_NewString(context, "Owned");
}
fn pendingKey(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = x.em.Engine.fromContext(context.?);
    const reason = c.JS_NewError(context); rawPut(engine, "actualKeyReason", reason);
    _ = c.JS_Throw(context, reason);
    return c.JS_NewString(context, "OWNED_KEY"); // Success value plus actual pending.
}
fn gc(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    c.JS_RunGC(x.em.Engine.fromContext(context.?).runtime); return c.pi_js_undefined();
}
fn prepare(engine: *x.em.Engine) !void {
    const api = try subject.create(engine); defer engine.freeValue(api); try put(engine, "actualAuthHelpers", api);
    const context = try subject.defaultProviderAuthContext(engine); defer engine.freeValue(context); try put(engine, "actualAuthContext", context);
    try engine.bindFunction("actualPrivateData", privateData, 0); try engine.bindFunction("actualFatalB", fatalB, 0);
    try engine.bindFunction("actualCapturedData", capturedData, 0); try engine.bindFunction("actualPendingKey", pendingKey, 0);
    try engine.bindFunction("actualGc", gc, 0);
}
fn read(engine: *x.em.Engine, name: [*:0]const u8) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    return engine.checked(c.JS_GetPropertyStr(engine.context, global, name));
}
fn eval(engine: *x.em.Engine, source: []const u8) !void {
    const value = try engine.evalModule(source, "actual-auth-successor-control.mjs"); engine.freeValue(value);
}
fn sameOperation(comptime fatal: bool) !void {
    inline for (.{ "getter", "call", "coercion" }) |operation| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
        const operation_source = if (std.mem.eql(u8, operation, "getter"))
            "const input={get ctx(){operationA=actualPrivateData();FATAL;throw operationA},credential:{key:'x'},signal:{throwIfAborted(){}}};await actualAuthHelpers.envApiKeyAuth('Owned',[]).resolve(input);"
        else if (std.mem.eql(u8, operation, "call"))
            "await actualAuthHelpers.envApiKeyAuth('Owned',[]).login({signal:{throwIfAborted(){}},prompt(){operationA=actualPrivateData();FATAL;throw operationA}});"
        else
            "await actualAuthHelpers.envApiKeyAuth({[Symbol.toPrimitive](){operationA=actualPrivateData();FATAL;throw operationA}},[]).login({signal:{throwIfAborted(){}},prompt(){throw Error('must not enter')}});";
        const substituted = try std.mem.replaceOwned(u8, engine.gpa, operation_source, "FATAL", if (fatal) "actualFatalB()" else "void 0"); defer engine.gpa.free(substituted);
        const source = try std.mem.concat(engine.gpa, u8, &.{ "globalThis.operationA=undefined;globalThis.operationCaught=undefined;try{", substituted, "}catch(error){globalThis.operationCaught=error}export const done=true;" }); defer engine.gpa.free(source);
        const result = engine.evalModule(source, "actual-auth-same-operation.mjs");
        if (fatal) {
            if (result) |value| { engine.freeValue(value); return error.ActualFatalBWasSwallowed; } else |err| try std.testing.expect(err == error.JavaScriptException);
            const chosen = engine.captured_exception orelse return error.RequiredActualFatalB;
            const b = try read(engine, "actualB"); defer engine.freeValue(b); const a = try read(engine, "operationA"); defer engine.freeValue(a);
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, chosen, b)); try std.testing.expect(!c.JS_IsStrictEqual(engine.context, a, b));
        } else {
            const value = try result; engine.freeValue(value);
            const a = try read(engine, "operationA"); defer engine.freeValue(a); const caught = try read(engine, "operationCaught"); defer engine.freeValue(caught);
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, a, caught)); try std.testing.expect(!c.JS_IsUncatchableError(a));
        }
        try std.testing.expect(engine.native_fatal_invocation == null);
        try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    }
}
test "AI auth successor SAME getter call coercion private DATA A throw stays ordinary" { try sameOperation(false); }
test "AI auth successor SAME getter call coercion actual current B wins over DATA A" { try sameOperation(true); }
test "AI auth successor direct host factory retains actual B1 and leaves captured DATA ordinary" {
    inline for (.{ false, true }) |fatal| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
        const input = try engine.eval(if (fatal)
            "globalThis.factoryNext=0;({get name(){actualFatalB();return'Owned'},get isSubscription(){factoryNext++;return false},loginLabel:'Owned',load(){return Promise.resolve({})}})"
        else
            "globalThis.factoryNext=0;({get name(){return actualCapturedData()},get isSubscription(){factoryNext++;return false},loginLabel:'Owned',load(){return Promise.resolve({})}})"
        , "actual-direct-host-input.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(input);
        const suppression = engine.native_exception_diagnostics_suppressed;
        const result = subject.lazyOAuth(engine, input); // Direct host call, no callback wrapper.
        if (fatal) {
            if (result) |value| { engine.freeValue(value); return error.DirectFactoryLostActualB1; } else |err| try std.testing.expect(err == error.JavaScriptException);
            const chosen = engine.captured_exception orelse return error.RequiredDirectFatalB;
            const b = try read(engine, "actualB"); defer engine.freeValue(b); try std.testing.expect(c.JS_IsStrictEqual(engine.context, chosen, b));
        } else { const value = try result; engine.freeValue(value); }
        const count = try read(engine, "factoryNext"); defer engine.freeValue(count);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, count, c.JS_NewInt32(engine.context, if (fatal) 0 else 1)));
        try std.testing.expect(engine.native_fatal_invocation == null); try std.testing.expectEqual(suppression, engine.native_exception_diagnostics_suppressed);
    }
}
test "AI auth successor successful key conversion pending reason precedes actual env getter" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"actual-key-control"});
    try eval(engine,
        \\globalThis.keyGetterCalls=0;Object.defineProperty(process.env,'OWNED_KEY',{get(){keyGetterCalls++;return'owned'}});
        \\let caught;try{await actualAuthContext.env({[Symbol.toPrimitive]:actualPendingKey})}catch(error){caught=error}
        \\if(caught!==actualKeyReason||keyGetterCalls!==0)throw Error('key success+pending ordering');
    );
}
test "AI auth successor prior job iterator result abort temporaries and iteration name retire before next callback" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    try eval(engine,
        \\function held(name,value){globalThis[name+'Weak']=new WeakRef(value);globalThis['take'+name]=()=>{const result=value;value=undefined;return result}}
        \\held('Step',{done:false,value:'ONLY'});
        \\held('AbortResult',{});held('AbortMethod',function(){return takeAbortResult()});
        \\held('AbortSignal',{get throwIfAborted(){return takeAbortMethod()}});
        \\held('Name',{});held('RejectedName',{});
    );
    c.JS_ClearKeptObjects(engine.runtime);
    try eval(engine,
        \\const assert=(ok,message)=>{if(!ok)throw Error(message)};
        \\let step=0;const one=actualAuthHelpers.envApiKeyAuth('Owned',{[Symbol.iterator](){return{next(){return step++===0?takeStep():{done:true}}}}});
        \\await one.resolve({ctx:{env(){actualGc();assert(StepWeak.deref()===undefined,'IteratorStep result retained into ctx.env');return undefined}},signal:{throwIfAborted(){}}});
        \\let aborts=0;await actualAuthHelpers.envApiKeyAuth('Owned',[]).login({get signal(){return aborts++===0?takeAbortSignal():{throwIfAborted(){}}},get prompt(){actualGc();for(const name of ['AbortSignal','AbortMethod','AbortResult'])assert(globalThis[name+'Weak'].deref()===undefined,name+' retained into prompt getter');return()=> 'owned'} });
        \\let names=0;await actualAuthHelpers.envApiKeyAuth('Owned',{[Symbol.iterator](){return{next(){if(names++===0)return{done:false,value:takeName()};actualGc();assert(NameWeak.deref()===undefined,'previous envVar retained into next');return{done:true}}}}}).resolve({ctx:{env(){return undefined}},signal:{throwIfAborted(){}}});
        \\const reason={};let closed=0;try{await actualAuthHelpers.envApiKeyAuth('Owned',{[Symbol.iterator](){return{next(){return{done:false,value:takeRejectedName()}},return(){closed++;actualGc();assert(RejectedNameWeak.deref()===undefined,'rejected envVar retained into close');return{}}}}}).resolve({ctx:{env(){return Promise.reject(reason)}},signal:{throwIfAborted(){}}})}catch(error){assert(error===reason,'original rejection')}
        \\assert(closed===1,'close exactly once');
    );
}
const Retirement = struct {
    engine: *x.em.Engine,
    gpa: std.mem.Allocator,
    refs: usize = 1,
    armed: bool = true,
    token: c.JSValue,
    reason: ?c.JSValue = null,
    calls: usize = 0,
    fn release(self: *Retirement) void {
        self.refs -= 1;
        if (self.refs == 0) self.gpa.destroy(self);
    }
    fn disarm(self: *Retirement) void {
        // Host cleanup runs while context is live and BEFORE Engine teardown.
        // Surviving traced holders may subsequently free the heap record but
        // cannot publish an event or touch Engine/context during teardown.
        self.armed = false;
        const token = self.token; self.token = c.pi_js_undefined(); self.engine.freeValue(token);
        if (self.reason) |reason| { self.reason = null; self.engine.freeValue(reason); }
    }
};
fn releaseRetirement(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Retirement = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
    state.release();
}
fn markRetirement(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *Retirement = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
    c.JS_MarkValue(runtime, state.token, visit);
    if (state.reason) |reason| c.JS_MarkValue(runtime, reason, visit);
}
fn retireStep(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Retirement = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
    defer state.release();
    state.calls += 1;
    if (!state.armed) return;
    _ = state.engine.checked(state.engine.throwNativeOutOfMemoryFatal()) catch {};
    state.reason = c.JS_DupValue(state.engine.context, state.engine.captured_exception.?);
}
fn takeNativeStep(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const state: *Retirement = @ptrCast(@alignCast(c.JS_GetOpaque(roots[0], c.JS_GetClassID(roots[0])).?));
    const token = state.token; state.token = c.pi_js_undefined(); return token;
}
test "AI auth successor actual iterator result retirement fatal B preempts ctx env with exact reason" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const state = try engine.gpa.create(Retirement);
    state.* = .{ .engine = engine, .gpa = engine.gpa, .token = c.pi_js_undefined() };
    defer { state.disarm(); state.release(); }
    var class: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Actual owned iterator result retirement", .finalizer = retireStep };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    state.token = try engine.checked(c.JS_NewObjectClass(engine.context, class)); _ = c.JS_SetOpaque(state.token, state); state.refs += 1;
    try @import("extensions/native_js_values.zig").define(engine, state.token, "done", c.pi_js_bool(engine.context, 0));
    try @import("extensions/native_js_values.zig").define(engine, state.token, "value", try engine.checked(c.JS_NewString(engine.context, "ONLY")));
    var holder_class: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &holder_class);
    const holder_definition: c.JSClassDef = .{ .class_name = "Traced owned retirement control", .finalizer = releaseRetirement, .gc_mark = markRetirement };
    if (c.JS_NewClass(engine.runtime, holder_class, &holder_definition) < 0) return error.OutOfMemory;
    const holder = try engine.checked(c.JS_NewObjectClass(engine.context, holder_class)); _ = c.JS_SetOpaque(holder, state); state.refs += 1;
    defer engine.freeValue(holder);
    var roots = [_]c.JSValue{holder};
    const take = try engine.checked(c.JS_NewCFunctionData2(engine.context, takeNativeStep, "actualTakeNativeStep", 0, 0, roots.len, &roots)); defer engine.freeValue(take);
    try put(engine, "actualTakeNativeStep", take);
    const result = engine.evalModule(
        \\globalThis.afterStepRetirement=0;
        \\try{await actualAuthHelpers.envApiKeyAuth('Owned',{[Symbol.iterator](){return{next:actualTakeNativeStep}}}).resolve({ctx:{env(){afterStepRetirement++;return undefined}},signal:{throwIfAborted(){}}})}catch(error){afterStepRetirement++}
    , "actual-auth-step-retirement.mjs");
    if (result) |value| { engine.freeValue(value); return error.RetirementFatalWasSwallowed; } else |err| try std.testing.expect(err == error.JavaScriptException);
    try std.testing.expectEqual(@as(usize, 1), state.calls);
    const chosen = engine.captured_exception orelse return error.RequiredRetirementFatal;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, chosen, state.reason.?));
    const count = try read(engine, "afterStepRetirement"); defer engine.freeValue(count);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, count, c.JS_NewInt32(engine.context, 0)));
    try std.testing.expect(engine.native_fatal_invocation == null);
}

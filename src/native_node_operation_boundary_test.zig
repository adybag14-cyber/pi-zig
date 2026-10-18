//! Actual Node Scope/ordinary callable producer boundaries. No source bridge,
//! fake AsyncFunction or compiler result is used by these native VM controls.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const Scope = @import("extensions/native_node_operation_scope.zig").Scope;
const functions = @import("extensions/native_node_module_callable.zig");
const Mode = enum { get_pair, call_pair, call_single };
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn callback(comptime mode: Mode) functions.Callback {
    return struct { fn invoke(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
        var s = Scope.init(engine); return s.finish(subject(&s, mode, args));
    } }.invoke;
}
fn subject(s: *Scope, comptime mode: Mode, args: []const c.JSValue) !c.JSValue {
    switch (mode) {
        .get_pair => { _ = try s.get(arg(args, 0), "first"); _ = try s.get(arg(args, 0), "second"); },
        .call_pair => { _ = try s.call(arg(args, 0), c.pi_js_undefined(), &.{}); _ = try s.call(arg(args, 1), c.pi_js_undefined(), &.{}); },
        .call_single => { _ = try s.call(arg(args, 0), c.pi_js_undefined(), &.{}); },
    }
    return c.pi_js_undefined();
}
fn makeData(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = v.em.Engine.fromContext(context.?);
    // Genuine private Error DATA, not an actual failed allocator or a fatal
    // producer. Take the exception and RETURN the exact object successfully.
    _ = engine.throwNativeOutOfMemory(); return c.JS_GetException(context);
}
const Fixture = struct {
    engine: *v.em.Engine,
    fn init() !Fixture {
        const engine = try v.em.Engine.init(std.testing.allocator, .{}); errdefer engine.deinit();
        try engine.bindFunction("actualPrivateData", makeData, 0);
        var s: v.Scope = .{ .engine = engine }; defer s.deinit();
        const global = try s.own(try engine.checked(c.JS_GetGlobalObject(engine.context)));
        inline for (.{ .{ "actualGetPair", Mode.get_pair, 1 }, .{ "actualCallPair", Mode.call_pair, 2 }, .{ "actualCallSingle", Mode.call_single, 1 } }) |entry| {
            const value = try s.own(try functions.create(engine, entry[0], entry[2], false, callback(entry[1]), &.{})); try s.put(global, entry[0], value);
        }
        return .{ .engine = engine };
    }
    fn deinit(self: Fixture) void { self.engine.deinit(); }
    fn check(self: Fixture, source: []const u8) !void {
        const result = try self.engine.eval(source, "C:/owned/node-boundary/observer.js", c.JS_EVAL_TYPE_GLOBAL); defer self.engine.freeValue(result);
        try std.testing.expect(c.JS_ToBool(self.engine.context, result) == 1);
        try std.testing.expectEqual(@as(usize, 0), self.engine.native_exception_diagnostics_suppressed);
        try std.testing.expect(self.engine.native_fatal_invocation == null);
    }
    fn savedData(self: Fixture) !c.JSValue {
        const global = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context)); defer self.engine.freeValue(global);
        return self.engine.checked(c.JS_GetPropertyStr(self.engine.context, global, "savedData"));
    }
};
test "native Node operation earlier successful getter DATA later thrown remains ordinary" {
    const f = try Fixture.init(); defer f.deinit(); const before = f.engine.native_allocation_generation;
    try f.check("globalThis.savedData=undefined;let caught;try{actualGetPair({get first(){savedData=actualPrivateData();return 1},get second(){throw savedData}})}catch(e){caught=e}caught===savedData");
    const data = try f.savedData(); defer f.engine.freeValue(data);
    try std.testing.expect(!c.JS_IsUncatchableError(data)); try std.testing.expectEqual(before +% 1, f.engine.native_allocation_generation);
}
test "native Node operation same getter creates and throws private DATA without fatal producer" {
    const f = try Fixture.init(); defer f.deinit();
    try f.check("globalThis.savedData=undefined;let caught;try{actualGetPair({get first(){savedData=actualPrivateData();throw savedData},get second(){throw Error('must not enter')}})}catch(e){caught=e}caught===savedData");
    const data = try f.savedData(); defer f.engine.freeValue(data); try std.testing.expect(!c.JS_IsUncatchableError(data));
}
test "native Node operation earlier successful call DATA later thrown remains ordinary" {
    const f = try Fixture.init(); defer f.deinit();
    try f.check("globalThis.savedData=undefined;let caught;try{actualCallPair(()=>{savedData=actualPrivateData();return 1},()=>{throw savedData})}catch(e){caught=e}caught===savedData");
    const data = try f.savedData(); defer f.engine.freeValue(data); try std.testing.expect(!c.JS_IsUncatchableError(data));
}
test "native Node operation same call creates and throws private DATA without fatal producer" {
    const f = try Fixture.init(); defer f.deinit();
    try f.check("globalThis.savedData=undefined;let caught;try{actualCallSingle(()=>{savedData=actualPrivateData();throw savedData})}catch(e){caught=e}caught===savedData");
    const data = try f.savedData(); defer f.engine.freeValue(data); try std.testing.expect(!c.JS_IsUncatchableError(data));
}
test "native Node operation ordinary untagged throw and successful caught DATA retain behavior" {
    const f = try Fixture.init(); defer f.deinit();
    try f.check("const reason={ordinary:true};let caught;try{actualCallSingle(()=>{throw reason})}catch(e){caught=e}actualCallSingle(()=>{const a=actualPrivateData();try{throw a}catch(e){return 7}})===undefined&&caught===reason");
}

const Probe = struct { engine: *v.em.Engine, first: ?c.JSValue = null, callbacks: usize = 0, cleanups: usize = 0, carrier_class: c.JSClassID = 0, restore_allocator: ?std.mem.Allocator = null };
fn probeFrom(value: c.JSValue) *Probe { return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?)); }
fn recordFatal(probe: *Probe) void {
    _ = probe.engine.throwNativeOutOfMemoryFatal(); const reason = c.JS_GetException(probe.engine.context);
    if (probe.first == null) probe.first = c.JS_DupValue(probe.engine.context, reason);
    _ = c.JS_Throw(probe.engine.context, reason);
}
fn cleanupC(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const probe = probeFrom(value); probe.cleanups += 1;
    if (probe.restore_allocator) |previous| {
        probe.restore_allocator = null; probe.engine.gpa = previous;
        recordFatal(probe); return;
    }
    // A fresh actual ordinary pending C at native retirement must not replace
    // B, already independently retained as the first genuine fatal producer.
    _ = c.JS_ThrowTypeError(probe.engine.context, "later actual cleanup C");
}
fn probeState(engine: *v.em.Engine, probe: *Probe) !c.JSValue {
    var state_class: c.JSClassID = 0;
    if (c.JS_NewClassID(engine.runtime, &state_class) == 0 or c.JS_NewClassID(engine.runtime, &probe.carrier_class) == 0) return error.OutOfMemory;
    const state_def: c.JSClassDef = .{ .class_name = "Actual native Node boundary probe" };
    const carrier_def: c.JSClassDef = .{ .class_name = "Actual native Node cleanup producer", .finalizer = cleanupC };
    if (c.JS_NewClass(engine.runtime, state_class, &state_def) < 0 or c.JS_NewClass(engine.runtime, probe.carrier_class, &carrier_def) < 0) return error.OutOfMemory;
    const value = try engine.checked(c.JS_NewObjectProtoClass(engine.context, c.pi_js_null(), state_class)); _ = c.JS_SetOpaque(value, probe); return value;
}
fn fatalCallback(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const probe = probeFrom(roots[0]); probe.callbacks += 1; recordFatal(probe);
    return c.JS_NewInt32(engine.context, 19); // Actual success with pending B.
}
fn countingCallback(_: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { probeFrom(roots[0]).callbacks += 1; return c.pi_js_undefined(); }
fn carrierFactory(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const probe = probeFrom(roots[0]); const value = try engine.checked(c.JS_NewObjectProtoClass(engine.context, c.pi_js_null(), probe.carrier_class)); _ = c.JS_SetOpaque(value, probe); return value;
}
fn takeFailure(engine: *v.em.Engine, result: c.JSValue, expected: c.JSValue) !void {
    defer engine.freeValue(result); try std.testing.expect(c.JS_IsException(result)); try std.testing.expect(c.JS_HasException(engine.context));
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, expected)); try std.testing.expect(c.JS_IsUncatchableError(reason));
}
test "native Node callable retained B1 stops callback with cleared pending slot" {
    const f = try Fixture.init(); defer f.deinit(); var probe: Probe = .{ .engine = f.engine };
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit(); const state = try s.own(try probeState(f.engine, &probe));
    const callable = try s.own(try functions.create(f.engine, "actualEntry", 0, false, countingCallback, &.{state}));
    var outer: v.em.Engine.NativeInvocation = .{}; f.engine.enterNativeInvocation(&outer);
    defer if (outer.active) {
        const value = f.engine.leaveNativeInvocation(&outer, c.pi_js_undefined()); f.engine.freeValue(value);
        if (c.JS_HasException(f.engine.context)) f.engine.freeValue(c.JS_GetException(f.engine.context));
    };
    _ = f.engine.throwNativeOutOfMemoryFatal(); const first = c.JS_GetException(f.engine.context); defer f.engine.freeValue(first);
    // VM pending is empty, and no diagnostic is needed: the real first event
    // is independently retained in the actual enclosing native invocation.
    const result = c.JS_Call(f.engine.context, callable, c.pi_js_undefined(), 0, null);
    try takeFailure(f.engine, result, first); try std.testing.expectEqual(@as(usize, 0), probe.callbacks);
}
test "native Node constructor first fatal survives actual receiver prototype finalizer C" {
    const f = try Fixture.init(); defer f.deinit(); var probe: Probe = .{ .engine = f.engine };
    defer if (probe.first) |reason| f.engine.freeValue(reason);
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit(); const state = try s.own(try probeState(f.engine, &probe));
    const actual = try s.own(try functions.create(f.engine, "ActualNodeConstructor", 0, true, fatalCallback, &.{state}));
    const factory = try s.own(try functions.create(f.engine, "actualPrototypeCarrier", 0, false, carrierFactory, &.{state}));
    const global = try s.own(try f.engine.checked(c.JS_GetGlobalObject(f.engine.context))); try s.put(global, "actualPrototypeCarrier", factory);
    const target = try s.own(try f.engine.eval("new Proxy(function NativeNewTarget(){},{get(target,key,receiver){if(key==='prototype')return actualPrototypeCarrier();return Reflect.get(target,key,receiver)}})", "C:/owned/node-boundary/new-target.js", c.JS_EVAL_TYPE_GLOBAL));
    const result = c.JS_CallConstructor2(f.engine.context, actual, target, 0, null);
    if (probe.first) |first| try takeFailure(f.engine, result, first) else { f.engine.freeValue(result); return error.MissingActualFatalProducer; }
    try std.testing.expectEqual(@as(usize, 1), probe.callbacks); try std.testing.expectEqual(@as(usize, 1), probe.cleanups);
    try std.testing.expect(f.engine.native_fatal_invocation == null); try std.testing.expectEqual(@as(usize, 0), f.engine.native_exception_diagnostics_suppressed);
}
fn throwSavedData(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const value = try v.js.global(engine, "savedData"); defer engine.freeValue(value);
    return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
}
test "native Node constructor earlier prototype DATA later callback throw stays ordinary" {
    const f = try Fixture.init(); defer f.deinit();
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
    const constructor = try s.own(try functions.create(f.engine, "ActualDataConstructor", 0, true, throwSavedData, &.{}));
    try s.put(try s.own(try f.engine.checked(c.JS_GetGlobalObject(f.engine.context))), "ActualDataConstructor", constructor);
    try f.check("globalThis.savedData=undefined;const target=new Proxy(function RealNewTarget(){},{get(target,key,receiver){if(key==='prototype'){savedData=actualPrivateData();return {}}return Reflect.get(target,key,receiver)}});let caught;try{Reflect.construct(ActualDataConstructor,[],target)}catch(e){caught=e}caught===savedData");
    const data = try f.savedData(); defer f.engine.freeValue(data); try std.testing.expect(!c.JS_IsUncatchableError(data));
}
test "native Node callable actual pending ordinary entry wins armed VM pressure before callback" {
    const f = try Fixture.init(); defer f.deinit(); var probe: Probe = .{ .engine = f.engine };
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit(); const state = try s.own(try probeState(f.engine, &probe));
    const callable = try s.own(try functions.create(f.engine, "actualPendingEntry", 0, false, countingCallback, &.{state}));
    const first = try s.object(); _ = c.JS_Throw(f.engine.context, c.JS_DupValue(f.engine.context, first));
    c.JS_SetMemoryLimit(f.engine.runtime, 1);
    const result = c.JS_Call(f.engine.context, callable, c.pi_js_undefined(), 0, null);
    c.JS_SetMemoryLimit(f.engine.runtime, f.engine.options.memory_limit); defer f.engine.freeValue(result);
    try std.testing.expect(c.JS_IsException(result)); const actual = c.JS_GetException(f.engine.context); defer f.engine.freeValue(actual);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, actual, first)); try std.testing.expect(!c.JS_IsUncatchableError(actual));
    try std.testing.expectEqual(@as(usize, 0), probe.callbacks); try std.testing.expect(f.engine.native_fatal_invocation == null);
}
fn actualAllocatorFailure(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const previous = engine.gpa;
    var fail = std.testing.FailingAllocator.init(previous, .{ .fail_index = 0 });
    engine.gpa = fail.allocator(); defer engine.gpa = previous;
    const bytes = try engine.gpa.alloc(u8, 32); defer engine.gpa.free(bytes);
    return c.pi_js_undefined();
}
test "native Node callable genuine GPA failure publishes actual fatal producer" {
    const f = try Fixture.init(); defer f.deinit(); const generation = f.engine.native_allocation_generation;
    var s: v.Scope = .{ .engine = f.engine }; defer s.deinit();
    const callable = try s.own(try functions.create(f.engine, "actualAllocatorFailure", 0, false, actualAllocatorFailure, &.{}));
    const result = c.JS_Call(f.engine.context, callable, c.pi_js_undefined(), 0, null);
    if (f.engine.native_allocation_exception) |first| try takeFailure(f.engine, result, first) else { f.engine.freeValue(result); return error.MissingActualAllocationProducer; }
    try std.testing.expectEqual(generation +% 1, f.engine.native_allocation_generation); try std.testing.expect(f.engine.native_fatal_invocation == null);
}

test "native Node Scope actual root append failure records allocator before carrier cleanup" {
    const f=try Fixture.init();defer f.deinit();var probe:Probe=.{.engine=f.engine};
    defer if(probe.first)|reason|f.engine.freeValue(reason);
    var setup:v.Scope=.{.engine=f.engine};defer setup.deinit();_=try setup.own(try probeState(f.engine,&probe));
    var carrier=try f.engine.checked(c.JS_NewObjectProtoClass(f.engine.context,c.pi_js_null(),probe.carrier_class));_=c.JS_SetOpaque(carrier,&probe);
    var owned=Scope.init(f.engine);try owned.pending();
    for(0..owned.values.inline_values.len)|_|_=try owned.own(c.pi_js_undefined());
    const previous=f.engine.gpa;var fail=std.testing.FailingAllocator.init(previous,.{.fail_index=0});
    probe.restore_allocator=previous;f.engine.gpa=fail.allocator();
    // The first real dynamic append fails. The sole incoming carrier restores
    // the allocator before its later fatal attempt; allocator B already owns
    // first-event precedence, and no raw value is freed twice.
    const generation=f.engine.native_allocation_generation;
    const transfer=carrier;carrier=c.pi_js_undefined();const outcome=owned.own(transfer);
    f.engine.gpa=previous;probe.restore_allocator=null;
    if(outcome)|_|{const result=try owned.finish(c.pi_js_undefined());f.engine.freeValue(result);return error.ExpectedActualAppendFailure;}else |err|{
        if(owned.finish(err))|result|{f.engine.freeValue(result);return error.ExpectedActualCarrierFatal;}else |actual|try std.testing.expectEqual(error.JavaScriptException,actual);
    }
    const first=probe.first orelse return error.MissingActualCarrierFatal;
    const reason=f.engine.captured_exception orelse return error.MissingActualCapturedReason;
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context,reason,first));try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(generation+%1,f.engine.native_allocation_generation);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context,first,f.engine.native_allocation_exception.?));
    try std.testing.expectEqual(@as(usize,1),probe.cleanups);try std.testing.expect(f.engine.native_fatal_invocation==null);
    try std.testing.expectEqual(@as(usize,0),f.engine.native_exception_diagnostics_suppressed);
}

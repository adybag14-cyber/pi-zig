//! Thirty-seven declared actual Node inspector/formatter entry/ownership controls.
//! Ordinary observers also accept the pinned Source node:util inspect/format pair.
//! Build installation, metadata, Source capture and runtime are separate steps.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const owned = @import("extensions/native_sdk_owned_completion.zig");
const inspect = @import("extensions/native_node_util_inspect.zig");
fn privateData(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = v.em.Engine.fromContext(context.?);
    _ = engine.throwNativeOutOfMemory();
    return c.JS_GetException(context);
}
fn flaggedData(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const value = privateData(context, receiver, argc, argv);
    c.JS_SetUncatchableError(context, value);
    return value;
}
fn fatalCleared(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = v.em.Engine.fromContext(context.?);
    var invocation: v.em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    _ = engine.throwNativeOutOfMemoryFatal();
    engine.freeValue(c.JS_GetException(context));
    return engine.leaveNativeInvocation(&invocation, c.pi_js_undefined());
}
fn publish(engine: *v.em.Engine, name: [:0]const u8, value: c.JSValue) !void {
    const global = try engine.checked(c.JS_GetGlobalObject(engine.context));
    defer engine.freeValue(global);
    if (c.JS_SetPropertyStr(engine.context, global, name, c.JS_DupValue(engine.context, value)) < 0)
        return error.ActualInspectControlPublicationFailed;
}
const Fixture = struct {
    engine: *v.em.Engine,
    exports: inspect.Exports,
    fn init() !Fixture {
        const engine = try v.em.Engine.init(std.testing.allocator, .{});
        errdefer engine.deinit();
        const inputs = try inspect.capturePrimordials(engine);
        const created = inspect.create(engine, inputs);
        var completion = owned.Completion.initVoid(engine, if (created) |_| {} else |err| @as(anyerror!void, err));
        inline for (std.meta.fields(inspect.Inputs)) |field| completion.release(@field(inputs, field.name));
        completion.finishVoid() catch |err| {
            if (created) |result| result.deinit(engine) else |_| {}
            return err;
        };
        const result = try created;
        errdefer result.deinit(engine);
        try publish(engine, "actualInspect", result.inspect);
        try publish(engine, "actualFormat", result.format);
        try engine.bindFunction("actualInspectPrivateData", privateData, 0);
        try engine.bindFunction("actualInspectFlaggedData", flaggedData, 0);
        try engine.bindFunction("actualInspectFatalCleared", fatalCleared, 0);
        return .{ .engine = engine, .exports = result };
    }
    fn deinit(self: Fixture) void { self.exports.deinit(self.engine); self.engine.deinit(); }
    fn run(self: Fixture, tail: []const u8) !void {
        const source = try std.mem.concat(self.engine.gpa, u8, &.{@embedFile("extensions/fixtures/native-node-inspect-observer.mjs"), "\n", tail});
        defer self.engine.gpa.free(source);
        const result = try self.engine.evalModule(source, "actual-node-inspect-observer.mjs");
        self.engine.freeValue(result);
    }
    fn data(self: Fixture) !c.JSValue {
        const global = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context));
        defer self.engine.freeValue(global);
        return self.engine.checked(c.JS_GetPropertyStr(self.engine.context, global, "savedInspectData"));
    }
};
fn observe(comptime name: []const u8) !void {
    const fixture = try Fixture.init(); defer fixture.deinit();
    try fixture.run(name ++ "(actualInspect);");
}
test "native actual inspect ordinary callable shape and retained original defaults" { try observe("observeInspectShape"); }
test "native actual inspect primitive UTF16 negative zero Symbol and BigInt" { try observe("observeInspectPrimitives"); }
test "native actual inspect numeric separators and actual string truncation" { try observe("observeInspectNumeric"); }
test "native actual inspect captured primordial ignores late global replacement" { try observe("observeInspectCapturedPrimordials"); }
test "native actual inspect custom callback receiver arguments and same inspector" { try observe("observeInspectCustomArguments"); }
test "native actual inspect custom ordinary throw keeps exact reason" { try observe("observeInspectOrdinaryCustomThrow"); }
test "native actual inspect actual toStringTag getter ordinary catch" { try observe("observeInspectTagCatch"); }
test "native actual inspect actual instance operator ordinary catch" { try observe("observeInspectInstanceCatch"); }
test "native actual inspect genuine proxy unwrap and revoked status" { try observe("observeInspectProxyDetails"); }
test "native actual inspect default assignment descriptor and getter order" { try observe("observeInspectDefaultAssignment"); }
test "native actual inspect same tag getter private DATA throw stays ordinary" {
    const fixture = try Fixture.init(); defer fixture.deinit();
    const generation = fixture.engine.native_allocation_generation;
    try fixture.run(
        \\globalThis.savedInspectData=undefined;
        \\const input={};Object.defineProperty(input,Symbol.toStringTag,{get(){savedInspectData=actualInspectPrivateData();throw savedInspectData;}});
        \\inspectAssert(actualInspect(input)==="{}","private tag error was caught");
    );
    const value = try fixture.data(); defer fixture.engine.freeValue(value);
    try std.testing.expect(!c.JS_IsUncatchableError(value));
    try std.testing.expectEqual(generation +% 1, fixture.engine.native_allocation_generation);
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
}
test "native actual inspect successful flagged private tag value remains DATA" {
    const fixture = try Fixture.init(); defer fixture.deinit();
    const generation = fixture.engine.native_allocation_generation;
    try fixture.run(
        \\globalThis.savedInspectData=undefined;
        \\const input={};Object.defineProperty(input,Symbol.toStringTag,{get(){savedInspectData=actualInspectFlaggedData();return savedInspectData;}});
        \\inspectAssert(actualInspect(input)==="{}","successful flagged tag DATA");
    );
    const value = try fixture.data(); defer fixture.engine.freeValue(value);
    try std.testing.expect(c.JS_IsUncatchableError(value));
    try std.testing.expectEqual(generation +% 1, fixture.engine.native_allocation_generation);
    try std.testing.expect(!c.JS_HasException(fixture.engine.context));
    try fixture.engine.checkNativeEntry();
}
test "native actual inspect retained allocator B1 bypasses ordinary tag catch" {
    const fixture = try Fixture.init(); defer fixture.deinit();
    const result = fixture.run(
        \\const input={};Object.defineProperty(input,Symbol.toStringTag,{get(){actualInspectFatalCleared();return "";}});
        \\actualInspect(input);
    );
    try std.testing.expectError(error.JavaScriptException, result);
    const first = fixture.engine.native_allocation_exception orelse return error.MissingActualInspectAllocationReason;
    const reason = fixture.engine.captured_exception orelse return error.MissingActualInspectCapturedReason;
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, first, reason));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
}

test "native actual inspect typed numeric and BigInt arrays use actual element formatting" { try observe("observeInspectTypedValues"); }
test "native actual inspect typed limits depth and exact Array range validation" { try observe("observeInspectTypedLimits"); }
test "native actual inspect null-prototype typed arrays retain original constructors and getters" { try observe("observeInspectTypedCaptured"); }
test "native actual inspect typed size and repeated live lengths are separate" { try observe("observeInspectTypedLengthReads"); }
test "native actual inspect typed prefix performs the live String method lookup" { try observe("observeInspectTypedPrefix"); }
test "native actual inspect typed formatter publishes each actual output Array index" { try observe("observeInspectTypedOutputSet"); }

const TypedProbe = struct {
    engine: *v.em.Engine,
    class_id: c.JSClassID = 0,
    made: bool = false,
    releases: u32 = 0,
    fatal: bool = false,
    first: ?c.JSValue = null,
    fn disable(self: *TypedProbe) void {
        self.fatal = false;
        if (self.first) |reason| {
            self.first = null;
            self.engine.freeValue(reason);
        }
    }
};
var typed_probe: ?*TypedProbe = null;
fn typedFinalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const probe: *TypedProbe = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    probe.releases += 1;
    if (probe.fatal) {
        probe.fatal = false;
        _ = probe.engine.throwNativeOutOfMemoryFatal();
        if (c.JS_HasException(probe.engine.context)) {
            const reason = c.JS_GetException(probe.engine.context);
            probe.first = c.JS_DupValue(probe.engine.context, reason);
            _ = c.JS_Throw(probe.engine.context, reason);
        }
    }
}
fn typedHolder(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const probe = typed_probe orelse return c.JS_ThrowInternalError(context, "Missing actual typed-array inspection probe");
    probe.engine.checkNativeEntry() catch return probe.engine.throwCaptured();
    if (probe.made) return c.JS_ThrowInternalError(context, "Actual inspection holder used twice");
    const value = c.JS_NewObjectClass(context, probe.class_id);
    if (c.JS_IsException(value)) return value;
    probe.made = true;
    _ = c.JS_SetOpaque(value, probe);
    return value;
}
fn typedCount(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const probe = typed_probe orelse return c.JS_ThrowInternalError(context, "Missing actual typed-array inspection probe");
    probe.engine.checkNativeEntry() catch return probe.engine.throwCaptured();
    return c.JS_NewUint32(context, probe.releases);
}
fn typedSetup(probe: *TypedProbe) !void {
    typed_probe = probe;
    if (c.JS_NewClassID(probe.engine.runtime, &probe.class_id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Actual inspect length temporary", .finalizer = typedFinalizer };
    if (c.JS_NewClass(probe.engine.runtime, probe.class_id, &definition) < 0) return error.OutOfMemory;
    try probe.engine.bindFunction("actualInspectLengthHolder", typedHolder, 0);
    try probe.engine.bindFunction("actualInspectLengthCount", typedCount, 0);
}
fn typedProgress(engine: *v.em.Engine) !c.JSValue {
    return engine.eval("globalThis.typedInspectProgress={reads:0,later:false,caught:false};typedInspectProgress", "actual-inspect-progress.js", c.JS_EVAL_TYPE_GLOBAL);
}
fn typedOwnFalse(engine: *v.em.Engine, progress: c.JSValue, name: [*:0]const u8) !void {
    // This retained literal's known own Boolean fields need no guest callback.
    const value = c.JS_GetPropertyStr(engine.context, progress, name);
    defer engine.freeValue(value);
    try std.testing.expect(c.JS_IsBool(value));
    try std.testing.expect(c.JS_ToBool(engine.context, value) == 0);
}
fn typedReadCount(engine: *v.em.Engine, progress: c.JSValue) !u32 {
    const value = c.JS_GetPropertyStr(engine.context, progress, "reads");
    defer engine.freeValue(value);
    try std.testing.expect(c.JS_IsNumber(value));
    var count: u32 = 0;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ToUint32(engine.context, &count, value));
    return count;
}
test "native actual inspect typed strict length temporary retires before the next length getter" {
    const fixture = try Fixture.init();
    var probe: TypedProbe = .{ .engine = fixture.engine };
    defer { probe.disable(); fixture.deinit(); typed_probe = null; }
    try typedSetup(&probe);
    const progress = try typedProgress(fixture.engine); defer fixture.engine.freeValue(progress);
    const generation = fixture.engine.native_allocation_generation;
    try fixture.run(
        \\const input=new Uint8Array([1]);
        \\Object.defineProperty(input,"length",{get(){
        \\  typedInspectProgress.reads++;
        \\  if(typedInspectProgress.reads===1)return actualInspectLengthHolder();
        \\  typedInspectProgress.later=true;
        \\  inspectAssert(actualInspectLengthCount()===1,"strict length operand retired before next getter");
        \\  return 1;
        \\}});
        \\inspectAssert(actualInspect(input)==="Uint8Array(1) [ 1 ]","real typed formatter after holder retirement");
    );
    try std.testing.expectEqual(@as(u32, 1), probe.releases);
    try std.testing.expectEqual(@as(u32, 3), try typedReadCount(fixture.engine, progress));
    try std.testing.expectEqual(generation, fixture.engine.native_allocation_generation);
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
}
test "native actual inspect typed length retirement fatal stops before another getter and guest catch" {
    const fixture = try Fixture.init();
    var probe: TypedProbe = .{ .engine = fixture.engine, .fatal = true };
    defer { probe.disable(); fixture.deinit(); typed_probe = null; }
    try typedSetup(&probe);
    const progress = try typedProgress(fixture.engine); defer fixture.engine.freeValue(progress);
    const generation = fixture.engine.native_allocation_generation;
    const result = fixture.run(
        \\const input=new Uint8Array([1]);
        \\Object.defineProperty(input,"length",{get(){
        \\  typedInspectProgress.reads++;
        \\  if(typedInspectProgress.reads===1)return actualInspectLengthHolder();
        \\  typedInspectProgress.later=true;return 1;
        \\}});
        \\try{actualInspect(input);}catch(reason){typedInspectProgress.caught=true;throw reason;}
    );
    try std.testing.expectError(error.JavaScriptException, result);
    const first = probe.first orelse return error.MissingActualTypedInspectFatal;
    const captured = fixture.engine.captured_exception orelse return error.MissingActualTypedInspectCaptured;
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, first, captured));
    try std.testing.expect(c.JS_IsUncatchableError(captured));
    try std.testing.expectEqual(generation +% 1, c.pi_js_native_allocation_error_generation(captured));
    try std.testing.expectEqual(@as(u32, 1), probe.releases);
    try std.testing.expectEqual(@as(u32, 1), try typedReadCount(fixture.engine, progress));
    try typedOwnFalse(fixture.engine, progress, "later");
    try typedOwnFalse(fixture.engine, progress, "caught");
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
}
test "native actual inspect typed repeated length ordinary private DATA keeps exact identity" {
    const fixture = try Fixture.init(); defer fixture.deinit();
    const generation = fixture.engine.native_allocation_generation;
    try fixture.run(
        \\globalThis.savedInspectData=actualInspectPrivateData();
        \\const input=new Uint8Array([1]);let reads=0,caught;
        \\Object.defineProperty(input,"length",{get(){if(++reads===1)return 1;throw savedInspectData;}});
        \\try{actualInspect(input);}catch(reason){caught=reason;}
        \\inspectAssert(reads===2&&caught===savedInspectData,"typed length ordinary private DATA identity");
    );
    const reason = try fixture.data(); defer fixture.engine.freeValue(reason);
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(generation +% 1, fixture.engine.native_allocation_generation);
    try std.testing.expect(!c.JS_HasException(fixture.engine.context));
    try fixture.engine.checkNativeEntry();
}

const TypedOrderProbe = struct {
    const Slot = struct { probe: *TypedOrderProbe, index: u32 };
    engine: *v.em.Engine,
    class_id: c.JSClassID = 0,
    slots: [3]Slot = undefined,
    used: u32 = 0,
    retired: u32 = 0,
    first_observed: ?u32 = null,
};
var typed_order_probe: ?*TypedOrderProbe = null;
fn typedOrderFinalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const slot: *TypedOrderProbe.Slot = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    const bit = @as(u32, 1) << @as(u5, @intCast(slot.index));
    if (slot.index == 0) slot.probe.first_observed = slot.probe.retired;
    slot.probe.retired |= bit;
}
fn typedOrderHolder(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const probe = typed_order_probe orelse return c.JS_ThrowInternalError(context, "Missing actual inspector order probe");
    probe.engine.checkNativeEntry() catch return probe.engine.throwCaptured();
    var index: u32 = 0;
    if (argc != 1 or !c.JS_IsNumber(argv[0]) or c.JS_ToUint32(context, &index, argv[0]) < 0 or index >= probe.slots.len)
        return c.JS_ThrowInternalError(context, "Invalid actual inspector holder index");
    const bit = @as(u32, 1) << @as(u5, @intCast(index));
    if (probe.used & bit != 0) return c.JS_ThrowInternalError(context, "Inspector holder reused");
    const value = c.JS_NewObjectClass(context, probe.class_id);
    if (c.JS_IsException(value)) return value;
    probe.used |= bit;
    _ = c.JS_SetOpaque(value, &probe.slots[index]);
    return value;
}
fn typedOrderSetup(probe: *TypedOrderProbe) !void {
    for (&probe.slots, 0..) |*slot, index| slot.* = .{ .probe = probe, .index = @intCast(index) };
    typed_order_probe = probe;
    if (c.JS_NewClassID(probe.engine.runtime, &probe.class_id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Actual inspect expression operands", .finalizer = typedOrderFinalizer };
    if (c.JS_NewClass(probe.engine.runtime, probe.class_id, &definition) < 0) return error.OutOfMemory;
    try probe.engine.bindFunction("actualInspectOrderHolder", typedOrderHolder, 1);
}
test "native actual inspect typed prefix second receiver and callee retire before the equality operand" {
    const fixture = try Fixture.init();
    var probe: TypedOrderProbe = .{ .engine = fixture.engine };
    defer { fixture.deinit(); typed_order_probe = null; }
    try typedOrderSetup(&probe);
    try fixture.run(
        \\const input=new Uint8Array([1]);
        \\const method=Object.getOwnPropertyDescriptor(String.prototype,"indexOf");
        \\const indexed=Object.getOwnPropertyDescriptor(String.prototype,"110");
        \\let visits=0,result;
        \\try {
        \\  Object.defineProperty(String.prototype,"indexOf",{configurable:true,value(){return 100;}});
        \\  Object.defineProperty(String.prototype,"110",{configurable:true,get(){
        \\    if(++visits===1)return actualInspectOrderHolder(0);
        \\    const receiver=actualInspectOrderHolder(1);
        \\    Object.defineProperty(receiver,"toLowerCase",{get(){
        \\      const capture=actualInspectOrderHolder(2);
        \\      return function(){if(!capture)throw Error("missing actual callee capture");return "different";};
        \\    }});
        \\    return receiver;
        \\  }});
        \\  result=actualInspect(input);
        \\} finally {
        \\  Object.defineProperty(String.prototype,"indexOf",method);
        \\  if(indexed)Object.defineProperty(String.prototype,"110",indexed);else delete String.prototype[110];
        \\}
        \\inspectAssert(visits===2&&result==="Uint8Array(1) [ 1 ]","actual selected prefix comparison");
    );
    try std.testing.expectEqual(@as(u32, 7), probe.used);
    try std.testing.expectEqual(@as(u32, 7), probe.retired);
    // Internal destruction order of the second receiver and its callee is not
    // prescribed here; both completed before the earlier comparison operand.
    try std.testing.expectEqual(@as(?u32, 6), probe.first_observed);
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
}
test "native actual inspect typed output receiver retires before its length value is added" {
    const fixture = try Fixture.init();
    var probe: TypedProbe = .{ .engine = fixture.engine };
    defer { probe.disable(); fixture.deinit(); typed_probe = null; }
    try typedSetup(&probe);
    try fixture.run(
        \\const input=new Uint8Array([9]);
        \\const prior=Object.getOwnPropertyDescriptor(Array.prototype,"0");
        \\const define=Object.defineProperty;let reads=0,conversions=0,result;
        \\const lengthValue={ [Symbol.toPrimitive](hint){
        \\  conversions++;
        \\  inspectAssert(hint==="default"&&actualInspectLengthCount()===1,"item receiver retired before length addition");
        \\  return 1;
        \\}};
        \\try {
        \\  define(Array.prototype,"0",{configurable:true,set(value){
        \\    if(value!=="9"){define(this,"0",{value,writable:true,enumerable:true,configurable:true});return;}
        \\    define(this,"0",{configurable:true,enumerable:true,get(){
        \\      if(++reads!==1)return "9";
        \\      const receiver=actualInspectLengthHolder();
        \\      define(receiver,"length",{get(){return lengthValue;}});
        \\      return receiver;
        \\    }});
        \\  }});
        \\  result=actualInspect(input);
        \\} finally {if(prior)define(Array.prototype,"0",prior);else delete Array.prototype[0];}
        \\inspectAssert(reads===2&&conversions===1&&result==="Uint8Array(1) [ 9 ]","actual typed layout length and join reads");
    );
    try std.testing.expectEqual(@as(u32, 1), probe.releases);
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
}


fn observeFormat(comptime name: []const u8) !void {
    const fixture = try Fixture.init(); defer fixture.deinit();
    try fixture.run(name ++ "(actualFormat,actualInspect);");
}
test "native actual inspect format ordinary shape and empty or single arguments" { try observeFormat("observeInspectFormatShape"); }
test "native actual inspect format Host template percent scan and trailing arguments" { try observeFormat("observeInspectFormatPlaceholders"); }
test "native actual inspect format conversion hints numeric defaults Symbol and BigInt" { try observeFormat("observeInspectFormatConversions"); }
test "native actual inspect format shared inspector and actual placeholder option literals" { try observeFormat("observeInspectFormatInspection"); }
test "native actual inspect format real rest Array inherited first index and skipped style value" { try observeFormat("observeInspectFormatRest"); }
test "native actual inspect format retains genuine string numeric and JSON primordials" { try observeFormat("observeInspectFormatCaptured"); }
test "native actual inspect format JSON lazy circular and ordinary catch identity" { try observeFormat("observeInspectFormatJson"); }
test "native actual inspect format circular calibration uses actual assignment and first error line" { try observeFormat("observeInspectFormatCalibration"); }
test "native actual inspect format JSON ordinary private DATA throw retains exact identity" {
    const fixture = try Fixture.init(); defer fixture.deinit();
    const generation = fixture.engine.native_allocation_generation;
    try fixture.run(
        \\globalThis.savedInspectData=actualInspectPrivateData();let observed;
        \\try{actualFormat("%j",{toJSON(){throw savedInspectData;}});}catch(reason){observed=reason;}
        \\inspectAssert(observed===savedInspectData,"ordinary private JSON throw identity");
    );
    const reason = try fixture.data(); defer fixture.engine.freeValue(reason);
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(generation +% 1, fixture.engine.native_allocation_generation);
    try std.testing.expect(!c.JS_HasException(fixture.engine.context));
    try fixture.engine.checkNativeEntry();
}
test "native actual inspect format JSON successful flagged return remains DATA" {
    const fixture = try Fixture.init(); defer fixture.deinit();
    const generation = fixture.engine.native_allocation_generation;
    try fixture.run(
        \\globalThis.savedInspectData=actualInspectFlaggedData();
        \\const expected=JSON.stringify(savedInspectData);
        \\inspectAssert(actualFormat("%j",{toJSON(){return savedInspectData;}})===expected,"successful flagged JSON return remains ordinary DATA");
    );
    const reason = try fixture.data(); defer fixture.engine.freeValue(reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(generation +% 1, fixture.engine.native_allocation_generation);
    try std.testing.expect(!c.JS_HasException(fixture.engine.context));
    try fixture.engine.checkNativeEntry();
}
test "native actual inspect format JSON actual fatal bypasses calibration and guest catch" {
    const fixture = try Fixture.init(); defer fixture.deinit();
    const progress = try typedProgress(fixture.engine); defer fixture.engine.freeValue(progress);
    const generation = fixture.engine.native_allocation_generation;
    const result = fixture.run(
        \\Object.defineProperty(Object.prototype,"a",{configurable:true,set(){typedInspectProgress.later=true;}});
        \\const value={toJSON(){typedInspectProgress.reads++;actualInspectFatalCleared();typedInspectProgress.later=true;return 0;}};
        \\try{actualFormat("%j",value);}catch(reason){typedInspectProgress.caught=true;throw reason;}
    );
    try std.testing.expectError(error.JavaScriptException, result);
    const first = fixture.engine.native_allocation_exception orelse return error.MissingActualFormatJsonFatal;
    const reason = fixture.engine.captured_exception orelse return error.MissingActualFormatJsonCaptured;
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, first, reason));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(generation +% 1, c.pi_js_native_allocation_error_generation(reason));
    try std.testing.expectEqual(@as(u32, 1), try typedReadCount(fixture.engine, progress));
    try typedOwnFalse(fixture.engine, progress, "later");
    try typedOwnFalse(fixture.engine, progress, "caught");
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
}
const formatCaseRetirement =
    \\const old=Object.getOwnPropertyDescriptor(Array.prototype,"0"),define=Object.defineProperty;
    \\let result;
    \\try{
    \\ define(Array.prototype,"0",{configurable:true,get(){
    \\  define(this,"0",{value:"%s %s",writable:true,enumerable:true,configurable:true});
    \\  define(this,"1",{configurable:true,get(){
    \\   typedInspectProgress.reads++;
    \\   return {owner:actualInspectLengthHolder(),[Symbol.toPrimitive](){return "first";}};
    \\  }});
    \\  define(this,"2",{configurable:true,get(){
    \\   typedInspectProgress.later=true;
    \\   inspectAssert(actualInspectLengthCount()===1,"prior matching case local retired before second argument getter");
    \\   return "second";
    \\  }});
    \\  return "%s %s";
    \\ }});
    \\ try{result=actualFormat();}catch(reason){typedInspectProgress.caught=true;throw reason;}
    \\}finally{if(old)define(Array.prototype,"0",old);else delete Array.prototype[0];}
    \\inspectAssert(result==="first second","actual matching case scan after local retirement");
;
test "native actual inspect format matching case local retires before its next index getter" {
    const fixture = try Fixture.init();
    var probe: TypedProbe = .{ .engine = fixture.engine };
    defer { probe.disable(); fixture.deinit(); typed_probe = null; }
    try typedSetup(&probe);
    const progress = try typedProgress(fixture.engine); defer fixture.engine.freeValue(progress);
    const generation = fixture.engine.native_allocation_generation;
    try fixture.run(formatCaseRetirement);
    try std.testing.expectEqual(@as(u32, 1), probe.releases);
    try std.testing.expectEqual(@as(u32, 1), try typedReadCount(fixture.engine, progress));
    try std.testing.expectEqual(generation, fixture.engine.native_allocation_generation);
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
}
test "native actual inspect format matching case retirement fatal stops next getter and catch" {
    const fixture = try Fixture.init();
    var probe: TypedProbe = .{ .engine = fixture.engine, .fatal = true };
    defer { probe.disable(); fixture.deinit(); typed_probe = null; }
    try typedSetup(&probe);
    const progress = try typedProgress(fixture.engine); defer fixture.engine.freeValue(progress);
    const generation = fixture.engine.native_allocation_generation;
    try std.testing.expectError(error.JavaScriptException, fixture.run(formatCaseRetirement));
    const first = probe.first orelse return error.MissingActualFormatCaseFatal;
    const reason = fixture.engine.captured_exception orelse return error.MissingActualFormatCaseCaptured;
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, first, reason));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(generation +% 1, c.pi_js_native_allocation_error_generation(reason));
    try std.testing.expectEqual(@as(u32, 1), probe.releases);
    try std.testing.expectEqual(@as(u32, 1), try typedReadCount(fixture.engine, progress));
    try typedOwnFalse(fixture.engine, progress, "later");
    try typedOwnFalse(fixture.engine, progress, "caught");
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
}

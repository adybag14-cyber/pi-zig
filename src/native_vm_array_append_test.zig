//! Narrow actual-VM controls for OP_append and the constructor OP_apply bridge.
//! Source comparisons execute literal operations in this same linked C runtime.
const std = @import("std");
const v = @import("extensions/native_public_values.zig");
const c = v.c;
const Engine = v.em.Engine;
const Scope = v.Scope;
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");

fn spreadBody(s: *Scope, iterable: c.JSValue) !c.JSValue {
    const target = try v.array(s);
    var position: u32 = 0;
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    try boundary.finishStatus(c.JS_PiArrayAppend(s.engine.context, target, &position, iterable));
    return v.duplicate(s, target);
}
fn spread(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    return v.owned.finishValue(&scope, spreadBody(&scope, v.arg(args, 0)));
}
fn constructBody(s: *Scope, constructor: c.JSValue, new_target: c.JSValue, iterable: c.JSValue) !c.JSValue {
    const arguments = try v.own(s, try spread(s.engine, c.pi_js_undefined(), &.{iterable}, &.{}));
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    const result = try boundary.finishValue(s, c.JS_PiCallConstructorArray(s.engine.context, constructor, new_target, arguments));
    return v.duplicate(s, result);
}
fn construct(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    return v.owned.finishValue(&scope, constructBody(&scope, v.arg(args, 0), v.arg(args, 1), v.arg(args, 2)));
}
const NodeScope = @import("extensions/native_node_operation_scope.zig").Scope;
fn restBody(s: *NodeScope, args: []const c.JSValue) !c.JSValue {
    const generation = try s.beforeAllocation();
    const result = try s.checkedAllocation(c.JS_PiCreateRestArray(s.engine.context, @intCast(args.len), @constCast(args.ptr)), generation);
    return c.JS_DupValue(s.engine.context, result);
}
fn rest(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope = NodeScope.init(engine);
    return scope.finish(restBody(&scope, args));
}
fn prepareBody(s: *Scope) !void {
    const global = try v.global(s, "globalThis");
    const native = try v.own(s, try v.function.createArrow(s.engine, "nativeArraySpread", 1, spread, &.{}));
    try v.put(s, global, "nativeArraySpread", native);
    const constructor = try v.own(s, try v.function.createArrow(s.engine, "nativeArrayConstruct", 3, construct, &.{}));
    try v.put(s, global, "nativeArrayConstruct", constructor);
    const rest_function = try v.own(s, try v.function.createArrow(s.engine, "nativeRestArray", 0, rest, &.{}));
    try v.put(s, global, "nativeRestArray", rest_function);
    const hooks = try v.own(s, try retirement.createNativeRetirementHooks(s.engine));
    try v.put(s, global, "appendHooks", hooks);
}
fn prepare(engine: *Engine) !void {
    var scope: Scope = .{ .engine = engine };
    try v.owned.finishVoid(&scope, prepareBody(&scope));
    try run(engine, "globalThis.sourceArraySpread=items=>[...items];");
}
fn run(engine: *Engine, source: []const u8) !void {
    const namespace = try engine.evalModule(source, "actual-vm-array-append-control.mjs");
    engine.freeValue(namespace);
}
fn evaluate(engine: *Engine, source: []const u8) !c.JSValue {
    return engine.eval(source, "actual-vm-array-append-control.js", c.JS_EVAL_TYPE_GLOBAL);
}
fn record(engine: *Engine) !c.JSValue {
    return evaluate(engine, "appendHooks.record");
}

test "VM array append actual dense sparse unicode and Set spread identities" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    try run(engine,
        \\const marker={actual:"identity"};
        \\for(const items of [[marker,7],[],[,,5],"A\u{1F4A0}B",new Set([marker,5])]){
        \\ const source=sourceArraySpread(items),native=nativeArraySpread(items);
        \\ if(source.length!==native.length)throw Error("Actual spread length");
        \\ for(let i=0;i<source.length;i++){
        \\  if(!Object.is(source[i],native[i]))throw Error("Actual spread value identity");
        \\  const a=Object.getOwnPropertyDescriptor(source,String(i)),b=Object.getOwnPropertyDescriptor(native,String(i));
        \\  if(!a||!b||a.writable!==b.writable||a.enumerable!==b.enumerable||a.configurable!==b.configurable)throw Error("Actual spread data descriptor");
        \\ }
        \\}
    );
}
test "VM array append actual double iterator probe and selected next receiver" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    try run(engine,
        \\function trial(spread){
        \\ const trace=[],marker={};let probes=0,nexts=0,iterator;
        \\ const input={get [Symbol.iterator](){
        \\  trace.push("probe"+(++probes));
        \\  if(probes===1)return function(){throw Error("Optimization probe must not call")};
        \\  return function(){trace.push(this===input?"factory":"bad-factory");iterator={get next(){
        \\   trace.push("next-get");return function(){trace.push(this===iterator?"next":"bad-next");
        \\    return ++nexts===1?{get done(){trace.push("done");return false},get value(){trace.push("value");return marker}}:{done:true};
        \\   };
        \\  }};return iterator};
        \\ }};
        \\ const result=spread(input);
        \\ if(result.length!==1||result[0]!==marker)throw Error("Actual selected iterator result");
        \\ return trace;
        \\}
        \\const expected=["probe1","probe2","factory","next-get","next","done","value","next"];
        \\if(JSON.stringify(trial(sourceArraySpread))!==JSON.stringify(expected)||JSON.stringify(trial(nativeArraySpread))!==JSON.stringify(expected))throw Error("Actual OP_append lookup and receiver trace");
    );
}
test "VM array append actual next done value failure closes and keeps first reason" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    try run(engine,
        \\function trial(spread,kind){
        \\ const first={},secondary={},trace=[];let caught;
        \\ const iterator={get next(){if(kind==="next-get")throw first;return function(){
        \\  trace.push("next");if(kind==="next")throw first;
        \\  return {get done(){if(kind==="done")throw first;return false},get value(){throw first}};
        \\ }},get return(){trace.push("return-get");return function(){trace.push("return-call");throw secondary}}};
        \\ try{spread({[Symbol.iterator](){return iterator}})}catch(error){caught=error}
        \\ if(caught!==first)throw Error("Actual spread first abrupt reason");
        \\ const expected=kind==="next-get"?[]:["next","return-get","return-call"];
        \\ if(JSON.stringify(trace)!==JSON.stringify(expected))throw Error("Actual spread abrupt IteratorClose");
        \\}
        \\for(const kind of ["next-get","next","done","value"]){trial(sourceArraySpread,kind);trial(nativeArraySpread,kind)}
    );
}
test "VM array append host cursor keeps partial target and commits only success" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    try run(engine,
        \\globalThis.appendTarget=[];globalThis.appendReason={};globalThis.appendClosed=0;
        \\let calls=0;globalThis.appendInput={[Symbol.iterator](){return {next(){if(calls++===0)return {done:false,value:"retained"};throw appendReason},return(){appendClosed++;return 7}}}};
    );
    const target = try evaluate(engine, "appendTarget"); defer engine.freeValue(target);
    const input = try evaluate(engine, "appendInput"); defer engine.freeValue(input);
    const expected = try evaluate(engine, "appendReason"); defer engine.freeValue(expected);
    var position: u32 = 0;
    const status = c.JS_PiArrayAppend(engine.context, target, &position, input);
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    try std.testing.expectEqual(@as(c_int, -1), status);
    try std.testing.expectEqual(@as(u32, 0), position);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, expected, reason));
    try run(engine, "if(appendTarget.length!==1||appendTarget[0]!==\"retained\"||appendClosed!==1)throw Error(\"Actual partial append and abrupt close\");");
}
test "VM array append cursor preserves the actual uint32 tagged wraparound" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    const target = try evaluate(engine, "globalThis.appendTarget={}"); defer engine.freeValue(target);
    const input = try evaluate(engine, "[\"high\",\"wrapped\"]"); defer engine.freeValue(input);
    var position: u32 = std.math.maxInt(u32);
    try std.testing.expectEqual(@as(c_int, 0), c.JS_PiArrayAppend(engine.context, target, &position, input));
    try std.testing.expectEqual(@as(u32, 1), position);
    try run(engine, "if(appendTarget[4294967295]!==\"high\"||appendTarget[0]!==\"wrapped\")throw Error(\"Actual tagged append position\");");
}
test "VM array append preexisting pending reason prevents every iterator getter" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    try run(engine, "globalThis.appendReads=0;globalThis.appendInput={get [Symbol.iterator](){appendReads++;throw Error(\"Must not reach iterator\")}};");
    const target = try evaluate(engine, "[]"); defer engine.freeValue(target);
    const input = try evaluate(engine, "appendInput"); defer engine.freeValue(input);
    const expected = try evaluate(engine, "({pending:\"actual\"})"); defer engine.freeValue(expected);
    var position: u32 = 11;
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, expected));
    const status = c.JS_PiArrayAppend(engine.context, target, &position, input);
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    try std.testing.expectEqual(@as(c_int, -1), status);
    try std.testing.expectEqual(@as(u32, 11), position);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, expected));
    try run(engine, "if(appendReads!==0)throw Error(\"Pending entry ran guest iterator\");");
}
test "VM array append same iterator getter born private DATA stays ordinary" {
    inline for (.{ false, true }) |native| {
        const engine = try Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try prepare(engine);
        try run(engine, if (native) "globalThis.selectedAppend=nativeArraySpread;" else "globalThis.selectedAppend=sourceArraySpread;");
        try run(engine,
            \\let probes=0,reason,caught;
            \\const input={get [Symbol.iterator](){if(++probes===1)return ()=>{};reason=appendHooks.freshPrivateData();throw reason}};
            \\try{selectedAppend(input)}catch(error){caught=error}
            \\if(probes!==2||caught!==reason||!appendHooks.isUnmarkedPrivateData(reason))throw Error("Actual private DATA remains ordinary");
        );
        try std.testing.expect(engine.native_fatal_invocation == null);
        try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    }
}
test "VM array append actual current native failure preempts older private DATA" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    const observed = try record(engine); defer engine.freeValue(observed);
    try std.testing.expectError(error.JavaScriptException, engine.evalModule(
        \\let probes=0;const input={get [Symbol.iterator](){
        \\ if(++probes===1)return ()=>{};
        \\ const old=appendHooks.freshPrivateData();appendHooks.raiseNativeFatal();throw old;
        \\}};
        \\try{nativeArraySpread(input)}catch(error){appendHooks.visit(3)}
    , "actual-vm-array-append-fatal.mjs"));
    try retirement.verifyRecordedActualNativeFatal(engine, observed);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "VM array append normal iterator retirement failure leaves cursor uncommitted" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    const observed = try record(engine); defer engine.freeValue(observed);
    const target = try evaluate(engine, "[]"); defer engine.freeValue(target);
    const input = try evaluate(engine, "({[Symbol.iterator](){return {holder:appendHooks.make(0),next(){return {done:true}}}}})"); defer engine.freeValue(input);
    try run(engine, "appendHooks.armFatal(0);");
    var position: u32 = 4;
    var boundary: v.guest.Boundary = .{ .engine = engine };
    try boundary.begin();
    const status = c.JS_PiArrayAppend(engine.context, target, &position, input);
    const outcome = boundary.finishStatus(status);
    try std.testing.expectError(error.JavaScriptException, outcome);
    try std.testing.expectEqual(@as(c_int, -1), status);
    try std.testing.expectEqual(@as(u32, 4), position);
    try retirement.verifyActualRetirementFatal(engine, observed, 0);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "VM array append constructor apply keeps real new target and mutated rest iterator" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    try run(engine,
        \\const marker={},replacement={};let trace=[];
        \\function Base(a,b){this.values=[a,b];this.target=new.target}
        \\class Derived extends Base {constructor(...args){super(...args)}}
        \\const descriptor=Object.getOwnPropertyDescriptor(Array.prototype,Symbol.iterator);
        \\Object.defineProperty(Array.prototype,Symbol.iterator,{configurable:true,get(){
        \\ if(this[0]!==marker)return descriptor.value;
        \\ trace.push("probe");return function(){trace.push("factory");let i=0;return {next(){return i++===0?{done:false,value:replacement}:i===2?{done:false,value:9}:{done:true}}}};
        \\}});
        \\try{
        \\ const source=new Derived(marker,2);const sourceTrace=JSON.stringify(trace);trace=[];
        \\ const native=nativeArrayConstruct(Base,Derived,[marker,2]);
        \\ if(source.target!==Derived||native.target!==Derived||Object.getPrototypeOf(source)!==Derived.prototype||Object.getPrototypeOf(native)!==Derived.prototype)throw Error("Actual constructor new.target and prototype");
        \\ if(source.values[0]!==replacement||native.values[0]!==replacement||source.values[1]!==9||native.values[1]!==9)throw Error("Actual rest iterator yielded constructor arguments");
        \\ if(sourceTrace!==JSON.stringify(["probe","probe","factory"])||JSON.stringify(trace)!==sourceTrace)throw Error("Actual constructor spread probes");
        \\}finally{Object.defineProperty(Array.prototype,Symbol.iterator,descriptor)}
    );
}
test "VM array append constructor apply uses actual argument cap and abrupt outcome" {
    const engine = try Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
    defer engine.deinit();
    try prepare(engine);
    try run(engine,
        \\let calls=0;function Base(){calls++}const huge=Array(65536);
        \\let source,native;
        \\try{new Base(...huge)}catch(error){source=error}
        \\try{nativeArrayConstruct(Base,Base,huge)}catch(error){native=error}
        \\if(!(source instanceof RangeError)||!(native instanceof RangeError)||source.message!==native.message||source.message!=="too many arguments in function call (only 65535 allowed)"||calls!==0)throw Error("Actual VM argument cap");
        \\const reason={};function Failing(){throw reason}
        \\let caught;try{nativeArrayConstruct(Failing,Failing,[1,2])}catch(error){caught=error}
        \\if(caught!==reason)throw Error("Actual constructor abrupt identity");
        \\const arrow=()=>{};let sourceType,nativeType;
        \\try{new arrow(...[1])}catch(error){sourceType=error}
        \\try{nativeArrayConstruct(arrow,arrow,[1])}catch(error){nativeType=error}
        \\if(!(sourceType instanceof TypeError)||!(nativeType instanceof TypeError)||sourceType.message!==nativeType.message)throw Error("Actual nonconstructor failure");
    );
}
test "VM array append constructor argument roots retire after actual base call" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    try run(engine,
        \\globalThis.argumentArray=[{holder:appendHooks.make(0)}];
        \\globalThis.argumentDuring=false;
        \\globalThis.ArrayBase=function(argument){delete argumentArray[0];argumentDuring=appendHooks.count(0)===0;this.ok=true};
    );
    const constructor = try evaluate(engine, "ArrayBase"); defer engine.freeValue(constructor);
    const arguments = try evaluate(engine, "argumentArray"); defer engine.freeValue(arguments);
    var boundary: v.guest.Boundary = .{ .engine = engine };
    var scope: Scope = .{ .engine = engine };
    try boundary.begin();
    const outcome = boundary.finishValue(&scope, c.JS_PiCallConstructorArray(engine.context, constructor, constructor, arguments));
    const owned_result: anyerror!c.JSValue = if (outcome) |value| c.JS_DupValue(engine.context, value) else |err| err;
    const result = try v.owned.finishValue(&scope, owned_result);
    defer engine.freeValue(result);
    try run(engine, "if(!argumentDuring||appendHooks.count(0)!==1)throw Error(\"Actual VM argument list root retirement\");");
    const okay = try engine.checked(c.JS_GetPropertyStr(engine.context, result, "ok")); defer engine.freeValue(okay);
    try std.testing.expect(c.JS_ToBool(engine.context, okay) == 1);
}

test "VM array append rest operand duplicates borrowed values until sole array retirement" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    var marker = try evaluate(engine, "({holder:appendHooks.make(0)})"); defer engine.freeValue(marker);
    const values = [_]c.JSValue{ marker, marker };
    var array = try engine.checked(c.JS_PiCreateRestArray(engine.context, values.len, @constCast(values[0..].ptr))); defer engine.freeValue(array);
    engine.freeValue(marker); marker = c.pi_js_undefined();
    try run(engine, "if(appendHooks.count(0)!==0)throw Error(\"Borrowed rest value was consumed\");");
    const first = try engine.checked(c.JS_GetPropertyUint32(engine.context, array, 0));
    const second = try engine.checked(c.JS_GetPropertyUint32(engine.context, array, 1));
    const same = c.JS_IsStrictEqual(engine.context, first, second);
    engine.freeValue(first); engine.freeValue(second);
    try std.testing.expect(same);
    engine.freeValue(array); array = c.pi_js_undefined();
    try run(engine, "if(appendHooks.count(0)!==1)throw Error(\"Actual rest array duplicates did not retire\");");
}
test "VM array append rest operand ignores mutable Array and iterator with actual empty case" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    try run(engine,
        \\const arrayDescriptor=Object.getOwnPropertyDescriptor(globalThis,"Array"),prototype=Array.prototype;
        \\const iteratorDescriptor=Object.getOwnPropertyDescriptor(prototype,Symbol.iterator),marker={};
        \\function collect(...args){return args}
        \\Object.defineProperty(globalThis,"Array",{configurable:true,get(){throw Error("Rest read global Array")}});
        \\Object.defineProperty(prototype,Symbol.iterator,{configurable:true,get(){throw Error("Rest iterated its arguments")}});
        \\try{
        \\ const source=collect(marker,7),native=nativeRestArray(marker,7);
        \\ if(source.length!==2||native.length!==2||source[0]!==marker||native[0]!==marker||source[1]!==7||native[1]!==7)throw Error("Actual rest operand values");
        \\ if(collect().length!==0||nativeRestArray().length!==0)throw Error("Actual empty rest operand");
        \\}finally{Object.defineProperty(globalThis,"Array",arrayDescriptor);Object.defineProperty(prototype,Symbol.iterator,iteratorDescriptor)}
    );
}

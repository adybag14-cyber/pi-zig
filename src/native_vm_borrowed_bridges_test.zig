//! Exact borrowed VM bridge controls. Literal Source operations run in the
//! same linked runtime; no guest implementation replaces the native operation.
const std = @import("std");
const v = @import("extensions/native_public_values.zig");
const c = v.c;
const Engine = v.em.Engine;
const Scope = v.Scope;
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");

fn prototypeBody(s: *Scope, constructor: c.JSValue) !c.JSValue {
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    return v.duplicate(s, try boundary.finishValue(s, c.JS_PiGetObjectPrototypeFromConstructor(s.engine.context, constructor)));
}
fn prototype(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    return v.owned.finishValue(&scope, prototypeBody(&scope, v.arg(args, 0)));
}
fn callBody(s: *Scope, function: c.JSValue, receiver: c.JSValue, arguments: c.JSValue) !c.JSValue {
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    return v.duplicate(s, try boundary.finishValue(s, c.JS_PiCallArray(s.engine.context, function, receiver, arguments)));
}
fn callArray(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    return v.owned.finishValue(&scope, callBody(&scope, v.arg(args, 0), v.arg(args, 1), v.arg(args, 2)));
}
fn nextOwned(engine: *Engine, iterator: c.JSValue, done: *bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    const outcome: anyerror!c.JSValue = body: {
        var boundary: v.guest.Boundary = .{ .engine = engine };
        boundary.begin() catch |err| break :body err;
        const key = boundary.finishValue(&scope, c.JS_PiForInNext(engine.context, iterator, done)) catch |err| break :body err;
        break :body v.duplicate(&scope, key);
    };
    return v.owned.finishValue(&scope, outcome);
}
fn collectRow(s: *Scope, result: c.JSValue, position: u32, incoming: c.JSValue, visitor: c.JSValue) !void {
    const key = try v.own(s, incoming);
    try v.index(s, result, position, key);
    if (!c.JS_IsUndefined(visitor)) _ = try v.call(s, visitor, c.pi_js_undefined(), &.{key});
}
fn collectBody(s: *Scope, input: c.JSValue, visitor: c.JSValue) !c.JSValue {
    const result = try v.array(s);
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    const iterator = try boundary.finishValue(s, c.JS_PiForInStart(s.engine.context, input));
    var position: u32 = 0;
    var steps: usize = 0;
    while (true) {
        try v.poll(s.engine, &steps);
        var done = false;
        const key = try nextOwned(s.engine, iterator, &done);
        if (done) {
            var completion = v.owned.Completion.initVoid(s.engine, {});
            completion.release(key);
            try completion.finishVoid();
            break;
        }
        var row: Scope = .{ .engine = s.engine };
        try v.owned.finishVoid(&row, collectRow(&row, result, position, key, visitor));
        position += 1;
    }
    return v.duplicate(s, result);
}
fn collect(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    return v.owned.finishValue(&scope, collectBody(&scope, v.arg(args, 0), v.arg(args, 1)));
}
fn prepareBody(s: *Scope) !void {
    const global = try v.global(s, "globalThis");
    inline for (.{
        .{ "nativePrototype", 1, prototype },
        .{ "nativeForIn", 2, collect },
        .{ "nativeCallArray", 3, callArray },
    }) |entry| {
        const function = try v.own(s, try v.function.createArrow(s.engine, entry[0], entry[1], entry[2], &.{}));
        try v.put(s, global, entry[0], function);
    }
    const hooks = try v.own(s, try retirement.createNativeRetirementHooks(s.engine));
    try v.put(s, global, "bridgeHooks", hooks);
}
fn run(engine: *Engine, source: []const u8) !void {
    const namespace = try engine.evalModule(source, "actual-vm-borrowed-bridge-control.mjs");
    engine.freeValue(namespace);
}
fn evaluate(engine: *Engine, source: []const u8) !c.JSValue {
    return engine.eval(source, "actual-vm-borrowed-bridge-control.js", c.JS_EVAL_TYPE_GLOBAL);
}
fn prepare(engine: *Engine) !void {
    var scope: Scope = .{ .engine = engine };
    try v.owned.finishVoid(&scope, prepareBody(&scope));
    try run(engine,
        \\const apply=Function.prototype.apply, reflectApply=Reflect.apply, construct=Reflect.construct, getPrototype=Object.getPrototypeOf;
        \\globalThis.sourcePrototype=constructor=>getPrototype(construct(function(){},[],constructor));
        \\globalThis.sourceCallArray=(fn,receiver,args)=>reflectApply(apply,fn,[receiver,args]);
        \\globalThis.sourceForIn=function(input,visitor){const keys=[];for(const key in input){keys.push(key);if(visitor!==undefined)visitor(key)}return keys};
    );
}

test "VM borrowed bridges prototype performs one live read and preserves returned object identity" {
    const engine = try Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
    defer engine.deinit();
    try prepare(engine);
    try run(engine,
        \\function trial(select){
        \\ const expected={},trace=[];let proxy;
        \\ proxy=new Proxy(function(){},{get(target,key,receiver){if(key==="prototype"){trace.push(receiver===proxy?"prototype":"bad receiver");return expected}return Reflect.get(target,key,receiver)}});
        \\ const result=select(proxy);
        \\ if(result!==expected||JSON.stringify(trace)!=='["prototype"]')throw Error("Actual live prototype binding");
        \\}
        \\trial(sourcePrototype);trial(nativePrototype);
        \\function C(){};C.prototype=17;
        \\if(sourcePrototype(C)!==Object.prototype||nativePrototype(C)!==Object.prototype)throw Error("Actual intrinsic Object fallback");
    );
}

test "VM borrowed bridges prototype fallback uses bound and proxy constructor foreign realms" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    const foreign = c.JS_NewContext(engine.runtime) orelse return error.OutOfMemory;
    defer c.JS_FreeContext(foreign);
    c.JS_SetContextOpaque(foreign, engine);
    const expected_source = "Object.prototype";
    const expected = try engine.checked(c.JS_Eval(foreign, expected_source, expected_source.len, "foreign-prototype.js", c.JS_EVAL_TYPE_GLOBAL));
    defer engine.freeValue(expected);
    inline for (.{
        "(function(){function C(){};C.prototype=17;return C})()",
        "(function(){function C(){};return C.bind(null)})()",
        "(function(){function C(){};return new Proxy(C,{get(t,k,r){return k==='prototype'?null:Reflect.get(t,k,r)}})})()",
    }) |source| {
        const constructor = try engine.checked(c.JS_Eval(foreign, source, source.len, "foreign-constructor.js", c.JS_EVAL_TYPE_GLOBAL));
        defer engine.freeValue(constructor);
        const actual = try prototype(engine, c.pi_js_undefined(), &.{constructor}, &.{});
        defer engine.freeValue(actual);
        const source_function = try evaluate(engine, "sourcePrototype");
        defer engine.freeValue(source_function);
        const arguments = [_]c.JSValue{constructor};
        const reference = try engine.checked(c.JS_Call(engine.context, source_function, c.pi_js_undefined(), arguments.len, @constCast(&arguments)));
        defer engine.freeValue(reference);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, expected, actual));
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, reference, actual));
    }
}

test "VM borrowed bridges prototype abrupt getter and revoked proxy keep actual failure" {
    const engine = try Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
    defer engine.deinit();
    try prepare(engine);
    try run(engine,
        \\for(const select of [sourcePrototype,nativePrototype]){
        \\ const reason={};const ctor=new Proxy(function(){},{get(t,k){if(k==="prototype")throw reason;return Reflect.get(t,k)}});
        \\ let caught;try{select(ctor)}catch(error){caught=error}
        \\ if(caught!==reason)throw Error("Prototype getter abrupt identity");
        \\ const revoked=Proxy.revocable(function(){},{});revoked.revoke();
        \\ let failure;try{select(revoked.proxy)}catch(error){failure=error}
        \\ if(!(failure instanceof TypeError)||!failure.message.includes("revoked"))throw Error("Actual revoked constructor");
        \\}
    );
}

test "VM borrowed bridges for in preserves primitive array prototype and string key rules" {
    const engine = try Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
    defer engine.deinit();
    try prepare(engine);
    try run(engine,
        \\const proto={z:1,shared:1},object=Object.create(proto);object.b=1;object[2]=1;object.a=1;
        \\Object.defineProperty(object,"shared",{value:2,enumerable:false});
        \\Object.defineProperty(object,"hidden",{value:3});object[Symbol("skip")]=1;
        \\for(const input of [object,[1,,3],"A\u{1F4A0}",17,true,17n,null,undefined]){
        \\ const source=sourceForIn(input),native=nativeForIn(input);
        \\ if(JSON.stringify(source)!==JSON.stringify(native))throw Error("Actual for-in key sequence");
        \\}
        \\if(JSON.stringify(nativeForIn(object))!=='["2","b","a","z"]')throw Error("Own non-enumerable shadow or prototype order");
    );
}

test "VM borrowed bridges for in actual snapshot skips deletion and excludes later additions" {
    const engine = try Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
    defer engine.deinit();
    try prepare(engine);
    try run(engine,
        \\function trial(enumerate){
        \\ const proto={inherited:1},input=Object.assign(Object.create(proto),{a:1,b:2,c:3});
        \\ return enumerate(input,key=>{if(key==="a"){delete input.b;input.added=4;proto.late=5}});
        \\}
        \\const source=trial(sourceForIn),native=trial(nativeForIn);
        \\if(JSON.stringify(source)!==JSON.stringify(native)||JSON.stringify(native)!=='["a","c","inherited"]')throw Error("Actual snapshot and deletion checks");
    );
}

test "VM borrowed bridges for in real proxy keys descriptors and prototype calls preserve trace" {
    const engine = try Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
    defer engine.deinit();
    try prepare(engine);
    try run(engine,
        \\function trial(enumerate){
        \\ const trace=[],target={a:1,b:2};let input;
        \\ input=new Proxy(target,{
        \\  ownKeys(t){trace.push("keys");return Reflect.ownKeys(t)},
        \\  getOwnPropertyDescriptor(t,k){trace.push("descriptor:"+k);return Reflect.getOwnPropertyDescriptor(t,k)},
        \\  getPrototypeOf(t){trace.push("prototype");return null},
        \\  has(t,k){trace.push("has:"+k);return Reflect.has(t,k)}
        \\ });
        \\ return {keys:enumerate(input),trace};
        \\}
        \\const source=trial(sourceForIn),native=trial(nativeForIn);
        \\if(JSON.stringify(source)!==JSON.stringify(native)||JSON.stringify(native.keys)!=='["a","b"]')throw Error("Actual proxy for-in protocol");
        \\if(native.trace.some(x=>x.startsWith("has:")))throw Error("VM proxy deletion exception changed");
    );
}

test "VM borrowed bridges for in snapshot and later inherited has failure keep exact ordinary reasons" {
    const engine = try Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
    defer engine.deinit();
    try prepare(engine);
    try run(engine,
        \\for(const enumerate of [sourceForIn,nativeForIn]){
        \\ for(const stage of ["keys","descriptor","prototype","has"]){
        \\  const reason={},trace=[];
        \\  const parent=new Proxy({p:1},{
        \\   ownKeys(t){trace.push("keys");if(stage==="keys")throw reason;return Reflect.ownKeys(t)},
        \\   getOwnPropertyDescriptor(t,k){trace.push("descriptor");if(stage==="descriptor")throw reason;return Reflect.getOwnPropertyDescriptor(t,k)},
        \\   getPrototypeOf(){trace.push("prototype");if(stage==="prototype")throw reason;return null},
        \\   has(){trace.push("has");throw reason}
        \\  });
        \\  let caught;try{enumerate(Object.create(parent))}catch(error){caught=error}
        \\  if(caught!==reason||trace[trace.length-1]!==stage)throw Error("Actual for-in abrupt phase "+stage);
        \\ }
        \\}
    );
}

test "VM borrowed bridges for in owns its input duplicate until iterator retirement" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    var input = try evaluate(engine, "({a:1,holder:bridgeHooks.make(0)})");
    defer engine.freeValue(input);
    var iterator = try engine.checked(c.JS_PiForInStart(engine.context, input));
    defer engine.freeValue(iterator);
    engine.freeValue(input); input = c.pi_js_undefined();
    try run(engine, "if(bridgeHooks.count(0)!==0)throw Error('Iterator did not retain borrowed input');");
    var count: usize = 0;
    while (true) {
        var done = false;
        const key = try engine.checked(c.JS_PiForInNext(engine.context, iterator, &done));
        defer engine.freeValue(key);
        if (done) break;
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
    try run(engine, "if(bridgeHooks.count(0)!==0)throw Error('Next consumed its borrowed iterator');");
    engine.freeValue(iterator); iterator = c.pi_js_undefined();
    try run(engine, "if(bridgeHooks.count(0)!==1)throw Error('Iterator input was not retired exactly once');");
}

test "VM borrowed bridges call array preserves live length index coercion strict receiver and no iterator" {
    const engine = try Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
    defer engine.deinit();
    try prepare(engine);
    try run(engine,
        \\function trial(call){
        \\ const trace=[],receiver={},marker={};
        \\ const args={get length(){trace.push("length");return {valueOf(){trace.push("length-number");return 2}}},
        \\ get 0(){trace.push("zero");return marker},get 1(){trace.push("one");return 7},
        \\ get [Symbol.iterator](){throw Error("Array-like call consulted iterable")}};
        \\ function fn(a,b){"use strict";trace.push("call");if(this!==receiver||a!==marker||b!==7)throw Error("Actual call operands");return marker}
        \\ const result=call(fn,receiver,args);
        \\ if(result!==marker)throw Error("Actual call return identity");
        \\ return trace;
        \\}
        \\const expected='["length","length-number","zero","one","call"]';
        \\if(JSON.stringify(trial(sourceCallArray))!==expected||JSON.stringify(trial(nativeCallArray))!==expected)throw Error("Actual apply argument-list order");
        \\for(const call of [sourceCallArray,nativeCallArray])for(const args of [null,undefined]){
        \\ const marker={};if(call(function(){"use strict";if(arguments.length)throw Error("Nullish arguments");return this},marker,args)!==marker)throw Error("Strict receiver or nullish apply");
        \\}
    );
}

test "VM borrowed bridges call array checks callable before reading array like arguments" {
    const engine = try Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
    defer engine.deinit();
    try prepare(engine);
    try run(engine,
        \\for(const call of [sourceCallArray,nativeCallArray]){
        \\ let reads=0,caught;
        \\ try{call({},null,{get length(){reads++;throw Error("Must not read")}})}catch(error){caught=error}
        \\ if(!(caught instanceof TypeError)||reads!==0)throw Error("Actual callable check must precede length");
        \\}
    );
}

test "VM borrowed bridges call array enforces actual argument cap and index abrupt completion" {
    const engine = try Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
    defer engine.deinit();
    try prepare(engine);
    try run(engine,
        \\for(const call of [sourceCallArray,nativeCallArray]){
        \\ let reached=0,reads=0,caught;function fn(){reached++}
        \\ try{call(fn,null,{length:65536,get 0(){reads++;return 1}})}catch(error){caught=error}
        \\ if(!(caught instanceof RangeError)||caught.message!=="too many arguments in function call (only 65535 allowed)"||reads!==0||reached!==0)throw Error("Actual argument cap");
        \\ const reason={},trace=[];caught=undefined;
        \\ try{call(fn,null,{length:3,get 0(){trace.push(0);return 1},get 1(){trace.push(1);throw reason},get 2(){trace.push(2);return 3}})}catch(error){caught=error}
        \\ if(caught!==reason||JSON.stringify(trace)!=="[0,1]"||reached!==0)throw Error("Actual indexed argument failure");
        \\}
    );
}

test "VM borrowed bridges call array actual argument copies survive callee and retire before next statement" {
    const engine = try Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
    defer engine.deinit();
    try prepare(engine);
    try run(engine,
        \\globalThis.argsForLifetime=[{holder:bridgeHooks.make(0)}];
        \\const receiver={};
        \\function callee(argument){"use strict";delete argsForLifetime[0];if(this!==receiver||bridgeHooks.count(0)!==0)throw Error("Argument list did not retain call operand");return 29}
        \\if(nativeCallArray(callee,receiver,argsForLifetime)!==29||bridgeHooks.count(0)!==1)throw Error("VM argument list did not retire after call");
    );
}

test "VM borrowed bridges same operation private DATA remains ordinary across all guest seams" {
    inline for (.{ "prototype", "for-in", "call-length", "call-index", "call-body" }) |kind| {
        inline for (.{ false, true }) |native| {
            const engine = try Engine.init(std.testing.allocator, .{});
            defer engine.deinit();
            try prepare(engine);
            try run(engine, "globalThis.bridgeKind='" ++ kind ++ "';globalThis.bridgeNative=" ++ (if (native) "true;" else "false;"));
            try run(engine,
                \\let reason,caught;
                \\function fail(){reason=bridgeHooks.freshPrivateData();throw reason}
                \\try{
                \\ if(bridgeKind==="prototype")(bridgeNative?nativePrototype:sourcePrototype)(new Proxy(function(){},{get(t,k){if(k==="prototype")return fail();return Reflect.get(t,k)}}));
                \\ else if(bridgeKind==="for-in")(bridgeNative?nativeForIn:sourceForIn)(new Proxy({},{ownKeys:fail}));
                \\ else {const invoke=bridgeNative?nativeCallArray:sourceCallArray;
                \\  if(bridgeKind==="call-length")invoke(()=>{},null,{get length(){return fail()}});
                \\  else if(bridgeKind==="call-index")invoke(()=>{},null,{length:1,get 0(){return fail()}});
                \\  else invoke(fail,null,[]);
                \\ }
                \\}catch(error){caught=error}
                \\if(caught!==reason||!bridgeHooks.isUnmarkedPrivateData(reason))throw Error("Same-operation DATA was promoted or replaced");
            );
            try std.testing.expect(engine.native_fatal_invocation == null);
            try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
        }
    }
}
test "VM borrowed bridges actual current B preempts older DATA at every guest seam" {
    inline for (.{ "prototype", "for-in", "call-length", "call-index", "call-body" }) |kind| {
        const engine = try Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try prepare(engine);
        try run(engine, "globalThis.bridgeKind='" ++ kind ++ "';");
        const observed = try evaluate(engine, "bridgeHooks.record");
        defer engine.freeValue(observed);
        try std.testing.expectError(error.JavaScriptException, engine.evalModule(
            \\function fail(){const prior=bridgeHooks.freshPrivateData();bridgeHooks.raiseNativeFatal();throw prior}
            \\try{
            \\ if(bridgeKind==="prototype")nativePrototype(new Proxy(function(){},{get(t,k){if(k==="prototype")return fail();return Reflect.get(t,k)}}));
            \\ else if(bridgeKind==="for-in")nativeForIn(new Proxy({},{ownKeys:fail}));
            \\ else if(bridgeKind==="call-length")nativeCallArray(()=>{},null,{get length(){return fail()}});
            \\ else if(bridgeKind==="call-index")nativeCallArray(()=>{},null,{length:1,get 0(){return fail()}});
            \\ else nativeCallArray(fail,null,[]);
            \\}catch(error){bridgeHooks.record.guestReached=true;bridgeHooks.visit(3)}
        , "actual-vm-bridge-current-fatal.mjs"));
        try retirement.verifyRecordedActualNativeFatal(engine, observed);
        try std.testing.expect(engine.native_fatal_invocation == null);
    }
}
test "VM borrowed bridges argument-list retirement B prevents the later guest statement" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    const observed = try evaluate(engine, "bridgeHooks.record");
    defer engine.freeValue(observed);
    try std.testing.expectError(error.JavaScriptException, engine.evalModule(
        \\globalThis.callArguments=[{holder:bridgeHooks.make(0)}];bridgeHooks.armFatal(0);
        \\function body(value){delete callArguments[0];if(bridgeHooks.count(0)!==0)throw Error("Argument root vanished during call");return 7}
        \\try{nativeCallArray(body,null,callArguments);bridgeHooks.record.guestReached=true}
        \\catch(error){bridgeHooks.visit(2);bridgeHooks.record.guestReached=true}
    , "actual-vm-bridge-list-retirement-fatal.mjs"));
    try retirement.verifyActualRetirementFatal(engine, observed, 0);
    const reached = try engine.checked(c.JS_GetPropertyStr(engine.context, observed, "guestReached"));
    defer engine.freeValue(reached);
    try std.testing.expect(c.JS_ToBool(engine.context, reached) == 0);
}
test "VM borrowed bridges every pending guard preserves its reason and skips guest work" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    try run(engine,
        \\globalThis.guardCalls=0;
        \\globalThis.guardConstructor=new Proxy(function(){},{get(){guardCalls++;throw Error("must not read")}});
        \\globalThis.guardInput=new Proxy({},{ownKeys(){guardCalls++;throw Error("must not enumerate")}});
        \\globalThis.guardArguments={get length(){guardCalls++;throw Error("must not build arguments")}};
        \\globalThis.guardFunction=function(){guardCalls++;throw Error("must not call")};
    );
    const constructor = try evaluate(engine, "guardConstructor"); defer engine.freeValue(constructor);
    const input = try evaluate(engine, "guardInput"); defer engine.freeValue(input);
    const arguments = try evaluate(engine, "guardArguments"); defer engine.freeValue(arguments);
    const function = try evaluate(engine, "guardFunction"); defer engine.freeValue(function);
    const expected = try evaluate(engine, "({pending:'real original'})"); defer engine.freeValue(expected);
    const ordinary_input = try evaluate(engine, "({a:1})"); defer engine.freeValue(ordinary_input);
    const iterator = try engine.checked(c.JS_PiForInStart(engine.context, ordinary_input)); defer engine.freeValue(iterator);
    inline for (0..4) |kind| {
        _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, expected));
        var done = false;
        const result = switch (kind) {
            0 => c.JS_PiGetObjectPrototypeFromConstructor(engine.context, constructor),
            1 => c.JS_PiForInStart(engine.context, input),
            2 => c.JS_PiForInNext(engine.context, iterator, &done),
            3 => c.JS_PiCallArray(engine.context, function, c.pi_js_undefined(), arguments),
            else => unreachable,
        };
        try std.testing.expect(c.JS_IsException(result));
        const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, expected, reason));
        if (kind == 2) try std.testing.expect(done);
    }
    var done = false;
    const first = try engine.checked(c.JS_PiForInNext(engine.context, iterator, &done));
    defer engine.freeValue(first);
    try std.testing.expect(!done);
    const expected_key = try evaluate(engine, "'a'"); defer engine.freeValue(expected_key);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, expected_key, first));
    try run(engine, "if(guardCalls!==0)throw Error('Pending bridge performed guest work');");
}
test "VM borrowed bridges ordinary call preserves successfully returned private DATA identity" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    try run(engine,
        \\const data=bridgeHooks.freshPrivateData();const receiver={};
        \\function body(){"use strict";if(this!==receiver)throw Error("Actual receiver");return data}
        \\if(nativeCallArray(body,receiver,[])!==data||!bridgeHooks.isUnmarkedPrivateData(data))throw Error("Successful native DATA was promoted");
    );
    try std.testing.expect(engine.native_fatal_invocation == null);
}

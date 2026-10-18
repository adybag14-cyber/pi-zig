//! Actual public CLI owner controls; Source and native functions are exercised
//! separately with fresh observer inputs. No expected transcript is injected.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const cli = @import("extensions/native_public_cli_args.zig");
const native = @import("extensions/native_node_function.zig");

fn install(engine: *em.Engine) !void {
    const reference = try engine.eval(@embedFile("extensions/fixtures/public-cli-args-c268-source.mjs"), "c268-cli-args-source.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(reference);
    const exports = try cli.create(engine);
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    if (c.JS_DefinePropertyValueStr(engine.context, global, "publicCliNative", exports, c.JS_PROP_C_W_E) < 0) return @import("extensions/native_js_values.zig").capture(engine);
}
fn check(engine: *em.Engine, source: []const u8) !void {
    const result = try engine.eval(source, "public-cli-owner-control.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    try std.testing.expectEqual(@as(c_int, 1), c.JS_ToBool(engine.context, result));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(!c.JS_HasException(engine.context));
}
fn makeData(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    _ = engine.throwNativeOutOfMemory();
    return c.JS_GetException(engine.context);
}
fn failAllocation(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var failing = std.testing.FailingAllocator.init(engine.gpa, .{ .fail_index = 0 });
    const original = engine.gpa; engine.gpa = failing.allocator();
    defer engine.gpa = original;
    const bytes = try engine.gpa.alloc(u8, 1); engine.gpa.free(bytes);
    return error.RequiredActualFailingAllocation;
}
fn installProducers(engine: *em.Engine) !void {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    inline for (.{ .{ "actualDataBirth", makeData }, .{ "actualGpaFailure", failAllocation } }) |item| {
        const callable = try native.create(engine, item[0], 0, item[1], &.{});
        if (c.JS_DefinePropertyValueStr(engine.context, global, item[0], callable, c.JS_PROP_C_W_E) < 0) return @import("extensions/native_js_values.zig").capture(engine);
    }
}
test "Public CLI actual parseArgs ordinary function shape and result identity" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try install(engine);
    try check(engine,
        \\(() => {
        \\ const n=publicCliNative.parseArgs, s=publicCliSource.parseArgs;
        \\ const shape=f=>[f.name,f.length,Object.hasOwn(f,"prototype"),Object.getPrototypeOf(f)===Function.prototype,Object.getOwnPropertyDescriptor(f,"prototype").writable];
        \\ if(JSON.stringify(shape(n))!==JSON.stringify(shape(s)))throw Error("function shape");
        \\ for(const f of [s,n]){
        \\   const first=f([]), second=Reflect.construct(f,[[]],class Alternate{});
        \\   if(first===second||first.messages===second.messages||Object.getPrototypeOf(second)!==Object.prototype)throw Error("fresh result");
        \\   if(!(first.unknownFlags instanceof Map)||Object.keys(first).join()!=="messages,fileArgs,unknownFlags,diagnostics")throw Error("literal field order");
        \\ }
        \\ return true;
        \\})()
    );
}
test "Public CLI actual frozen Source option matrix and recoverable diagnostics" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try install(engine);
    try check(engine,
        \\(() => {
        \\ const cases=[
        \\ [],
        \\ ["--help","-v","-c","--resume","--no-session","--no-tools","--no-builtin-tools","--no-extensions","--no-mcp","-ns","-np","--no-themes","-nc","--verbose","-a","-na","--offline"],
        \\ ["--provider","anthropic","--model","sonnet","--api-key","secret","--system-prompt","system","--session","s","--session-id","id","--fork","f","--session-dir","dir","--export","out","--name","name"],
        \\ ["--append-system-prompt","a","--append-system-prompt","b","-e","one","--extension","two","--skill","s","--prompt-template","p","--theme","dark","--theme","light"],
        \\ ["--models"," a, ,b ","--tools","+read,-bash","--exclude-tools"," x, y ","--thinking","max","--use-theme","dark","--tui-mode","regular"],
        \\ ["--tools","read,+bash","--tools","+read*","--thinking","wrong","--mode","wrong","--tui-mode","bad","--use-theme","--help","--mode","--version"],
        \\ ["--provider","--model","--models","--thinking","--session","-e","--exclude-tools"],
        \\ ["-p","---prompt","@","@@thing","message","--","--literal","@file","-x"],
        \\ ["--print","@file","--list-models","pattern","--list-models","@other","--use-theme","--tui-mode","--name"],
        \\ ["--flag=value","--flag","last","--boolean","--another","@file","-unknown","plain","--=empty","--flag=a=b"],
        \\ ["--mode","json","--mode","rpc","--mode","text","-n"," ","--tui-mode","fullscreen","--thinking","off","-p","-"],
        \\ ["--","@","@@","--","plain"]
        \\ ];
        \\ const normalize=r=>JSON.stringify({...r,unknownFlags:Array.from(r.unknownFlags)});
        \\ for(let i=0;i<cases.length;i++){
        \\   const expected=normalize(publicCliSource.parseArgs(cases[i].slice()));
        \\   const actual=normalize(publicCliNative.parseArgs(cases[i].slice()));
        \\   if(actual!==expected)throw Error("option case "+i+"\n"+expected+"\n"+actual);
        \\ }
        \\ return true;
        \\})()
    );
}
test "Public CLI actual live indices Map receiver and argument coercion order" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try install(engine);
    try check(engine,
        \\(() => {
        \\ function observe(parse){
        \\   const trace=[], savedMap=globalThis.Map;
        \\   let created;
        \\   globalThis.Map=function Map(){trace.push("new Map");created={get set(){trace.push("get set");return function(k,v){trace.push(["set",this===created,k,v]);}}};return created;};
        \\   const eq={ [Symbol.toPrimitive](hint){trace.push(["coerce equals",hint]);return 3;} };
        \\   const item={
        \\     get startsWith(){trace.push("get startsWith");return function(prefix){trace.push(["startsWith",this===item,prefix]);return prefix==="--";};},
        \\     get indexOf(){trace.push("get indexOf");return function(value){trace.push(["indexOf",this===item,value]);return eq;};},
        \\     get slice(){trace.push("get slice");return function(...args){trace.push(["slice",this===item,args.map(x=>x===eq?"eq":x)]);return args.length===2?"name":"value";};}
        \\   };
        \\   const args=new Proxy([item],{get(t,k,r){trace.push(["get args",String(k)]);return Reflect.get(t,k,r);}});
        \\   try{parse(args);}finally{globalThis.Map=savedMap;}
        \\   return JSON.stringify(trace);
        \\ }
        \\ const expected=observe(publicCliSource.parseArgs),actual=observe(publicCliNative.parseArgs);
        \\ if(actual!==expected)throw Error(expected+"\n"+actual);
        \\ return true;
        \\})()
    );
}
test "Public CLI actual csv callback shape and getter before callback creation" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try install(engine);
    try check(engine,
        \\(() => {
        \\ function observe(parse){
        \\   const trace=[];
        \\   const value={get split(){trace.push("get split");return function(separator){
        \\     trace.push(["split",this===value,separator]);
        \\     return {get map(){trace.push("get map");return function(callback){
        \\       trace.push(["map callback",callback.name,callback.length,Object.hasOwn(callback,"prototype")]);
        \\       const a=callback({trim(){trace.push("trim");return "kept";}});
        \\       return {get filter(){trace.push("get filter");return function(predicate){
        \\         trace.push(["filter callback",predicate.name,predicate.length,Object.hasOwn(predicate,"prototype")]);
        \\         const accepted=predicate({get length(){trace.push("get length");return {valueOf(){trace.push("length valueOf");return 4;}};}});
        \\         return accepted?[a]:[];
        \\       };}};
        \\     };}};
        \\   };}};
        \\   const parsed=parse(["--models",value]);
        \\   trace.push(parsed.models);
        \\   return JSON.stringify(trace);
        \\ }
        \\ const expected=observe(publicCliSource.parseArgs),actual=observe(publicCliNative.parseArgs);
        \\ if(actual!==expected)throw Error(expected+"\n"+actual);
        \\ return true;
        \\})()
    );
}
test "Public CLI actual tail IteratorClose precedence and abrupt next distinction" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try install(engine);
    try check(engine,
        \\(() => {
        \\ function observe(parse,kind){
        \\   const trace=[],first={},second={};let count=0;
        \\   const iterator={
        \\     get next(){trace.push("next getter");if(kind==="next-get")throw first;return function(){
        \\       trace.push("next call");if(kind==="next-call")throw first;if(kind==="primitive-next")return 7;
        \\       if(count++)return {done:true};
        \\       return {get done(){trace.push("done");return false;},get value(){trace.push("value");if(kind==="value-get")throw first;return {startsWith(){trace.push("body");throw first;}};}};
        \\     };},
        \\     get return(){trace.push("return getter");if(kind==="return-get")throw second;return function(){trace.push("return call");if(kind==="return-call")throw second;return 1;};}
        \\   };
        \\   const args={0:"--",length:1,slice(start){trace.push(["slice",start]);return {[Symbol.iterator](){trace.push("iterator call");return iterator;}};}};
        \\   try{parse(args);trace.push("unexpected success");}catch(e){trace.push(e===first?"first":e===second?"second":[e.name,e.message]);}
        \\   return JSON.stringify(trace);
        \\ }
        \\ for(const kind of ["body","return-get","return-call","next-get","next-call","value-get","primitive-next"]){
        \\   const expected=observe(publicCliSource.parseArgs,kind),actual=observe(publicCliNative.parseArgs,kind);
        \\   if(actual!==expected)throw Error(kind+"\n"+expected+"\n"+actual);
        \\ }
        \\ return true;
        \\})()
    );
}
test "Public CLI actual missing values repeat index reads and ordinary private DATA" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try install(engine); try installProducers(engine);
    try check(engine,
        \\(() => {
        \\ function observe(parse){
        \\   const trace=[];let nextReads=0;
        \\   const args=new Proxy(["--list-models","pattern"],{get(t,k,r){trace.push(String(k));if(k==="1")nextReads++;return Reflect.get(t,k,r);}});
        \\   const result=parse(args);return JSON.stringify([trace,nextReads,result.listModels]);
        \\ }
        \\ if(observe(publicCliSource.parseArgs)!==observe(publicCliNative.parseArgs))throw Error("repeated index reads");
        \\ for(const method of [false,true]){
        \\   let selected,after=false;
        \\   const args=method?[{get startsWith(){selected=actualDataBirth();throw selected;}}]:{get length(){selected=actualDataBirth();throw selected;}};
        \\   try{publicCliNative.parseArgs(args);after=true;}catch(reason){if(reason!==selected)throw Error("DATA identity");}
        \\   if(after)throw Error("missing DATA throw");
        \\ }
        \\ return true;
        \\})()
    );
    const reason = engine.native_allocation_exception orelse return error.RequiredActualDataBirth;
    try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
}
test "Public CLI actual callback GPA failure precedes prior private DATA and cleanup" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try install(engine); try installProducers(engine);
    const setup = try engine.eval(
        \\globalThis.priorCliData=actualDataBirth();
        \\globalThis.afterCliFatal=false;
        \\globalThis.actualCliArgs={get length(){try{actualGpaFailure()}catch(e){afterCliFatal=true;}afterCliFatal=true;return 0;}};
    , "actual-cli-producer.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(setup);
    const prior = c.JS_DupValue(engine.context, engine.native_allocation_exception.?); defer engine.freeValue(prior);
    try std.testing.expectError(error.JavaScriptException, engine.eval("publicCliNative.parseArgs(actualCliArgs)", "actual-cli-failure.js", c.JS_EVAL_TYPE_GLOBAL));
    const reason = engine.captured_exception orelse return error.RequiredActualCliFatal;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.native_allocation_exception.?));
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, reason, prior));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    const after = c.JS_GetPropertyStr(engine.context, global, "afterCliFatal"); defer engine.freeValue(after);
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ToBool(engine.context, after));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
test "Public CLI actual native loop cancellation is a current fatal producer" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try install(engine);
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    const exports = c.JS_GetPropertyStr(engine.context, global, "publicCliNative"); defer engine.freeValue(exports);
    const parse = c.JS_GetPropertyStr(engine.context, exports, "parseArgs"); defer engine.freeValue(parse);
    const input = try engine.checked(c.JS_NewArray(engine.context)); defer engine.freeValue(input);
    engine.cancelled.store(true, .release);
    var args = [_]c.JSValue{input};
    try std.testing.expectError(error.JavaScriptException, engine.checked(c.JS_Call(engine.context, parse, c.pi_js_undefined(), 1, &args)));
    engine.cancelled.store(false, .release);
    const reason = engine.captured_exception orelse return error.RequiredCurrentInterruption;
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}

fn collect(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    c.JS_RunGC(em.Engine.fromContext(context.?).runtime);
    return c.pi_js_undefined();
}
test "Public CLI actual modifier comparison temporaries retire before later getters" {
    inline for (.{ false, true }) |use_native| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        try install(engine); try engine.bindFunction("cliCollect", collect, 0);
        const selected = try engine.eval(if (use_native) "globalThis.cliSelected=publicCliNative.parseArgs" else "globalThis.cliSelected=publicCliSource.parseArgs", "cli-temp-selection.js", c.JS_EVAL_TYPE_GLOBAL);
        engine.freeValue(selected);
        const setup = try engine.eval(
            \\let firstLength={valueOf(){return 2;}},secondLength={valueOf(){return 2;}};
            \\globalThis.firstLengthWeak=new WeakRef(firstLength);globalThis.secondLengthWeak=new WeakRef(secondLength);
            \\let lengthReads=0;
            \\const modifiers={
            \\ get length(){
            \\   if(lengthReads++===0){const result=firstLength;firstLength=undefined;return result;}
            \\   cliCollect();if(firstLengthWeak.deref()!==undefined)throw Error("first length retained into second getter");
            \\   const result=secondLength;secondLength=undefined;return result;
            \\ },
            \\ get find(){cliCollect();if(secondLengthWeak.deref()!==undefined)throw Error("comparison retained into find");return function(){return undefined;};}
            \\};
            \\const entries={length:2,filter(){return modifiers;}};
            \\String.prototype.split=function(){return {map(){return {filter(){return entries;}};}};};
        , "cli-modifier-temp-setup.js", c.JS_EVAL_TYPE_GLOBAL);
        engine.freeValue(setup);
        try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
        engine.finishJob();
        try check(engine, "cliSelected(['--tools','unused']).tools===entries");
    }
}
test "Public CLI actual thinking template result retires before diagnostic push" {
    inline for (.{ false, true }) |use_native| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        try install(engine); try engine.bindFunction("cliCollect", collect, 0);
        const selected = try engine.eval(if (use_native) "globalThis.cliSelected=publicCliNative.parseArgs" else "globalThis.cliSelected=publicCliSource.parseArgs", "cli-template-selection.js", c.JS_EVAL_TYPE_GLOBAL);
        engine.freeValue(selected);
        const setup = try engine.eval(
            \\let joinedLevels={[Symbol.toPrimitive](hint){if(hint!=="string")throw Error("template hint");return "accepted levels";}};
            \\globalThis.joinedLevelsWeak=new WeakRef(joinedLevels);globalThis.cliDiagnosticObserved=false;
            \\Array.prototype.join=function(){const selected=joinedLevels;joinedLevels=undefined;return selected;};
            \\const nativePush=Array.prototype.push;
            \\Array.prototype.push=function(entry){
            \\ if(entry&&entry.type==="warning"){
            \\   cliCollect();if(joinedLevelsWeak.deref()!==undefined)throw Error("join result retained into push");
            \\   if(entry.message!=='Invalid thinking level "invalid". Valid values: accepted levels')throw Error("template message");
            \\   cliDiagnosticObserved=true;
            \\ }
            \\ return nativePush.call(this,entry);
            \\};
        , "cli-template-temp-setup.js", c.JS_EVAL_TYPE_GLOBAL);
        engine.freeValue(setup);
        try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
        engine.finishJob();
        try check(engine, "cliSelected(['--thinking','invalid']);cliDiagnosticObserved");
    }
}

//! Source-bound controls for the actual six public truncation exports.
//! Both algorithms consume the same genuine native Buffer module. This does
//! not establish upstream Node Buffer or complete public namespace parity.
const std = @import("std");
const x = @import("extensions/native_sdk_catalog_values.zig");
const c = x.c;
const truncation = @import("extensions/native_sdk_public_truncation.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");

fn install(engine: *x.em.Engine) !void {
    try @import("extensions/node_buffer.zig").install(engine);
    const source = try engine.eval(@embedFile("extensions/fixtures/sdk-public-truncation-c268-source.mjs"), "c268-public-truncation-source.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(source);
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishVoid(&s, installBody(&o));
}
fn installBody(o: *x.Ops) !void {
    const global = try o.own(c.JS_GetGlobalObject(o.s.engine.context));
    try o.put(global, "publicTruncationNative", try o.own(try truncation.create(o.s.engine)));
    try o.put(global, "truncHooks", try o.own(try retirement.createNativeRetirementHooks(o.s.engine)));
}
fn check(engine: *x.em.Engine, source: []const u8) !void {
    const value = try engine.eval(source, "actual-public-truncation-control.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(value);
    try std.testing.expectEqual(@as(c_int, 1), c.JS_ToBool(engine.context, value));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(!c.JS_HasException(engine.context));
}
fn execute(engine: *x.em.Engine, source: []const u8) !void {
    const value = try engine.eval(source, "actual-public-truncation-setup.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(value);
}
fn rawGlobal(engine: *x.em.Engine, name: [*:0]const u8) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    return engine.checked(c.JS_GetPropertyStr(engine.context, global, name));
}
test "SDK public truncation actual ordinary function shape and cached identities" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try install(engine);
    const again = try truncation.create(engine); defer engine.freeValue(again);
    const selected = try rawGlobal(engine, "publicTruncationNative"); defer engine.freeValue(selected);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, again, selected));
    try check(engine,
        \\(() => {
        \\ const n=publicTruncationNative,s=publicTruncationSource;
        \\ if(n.DEFAULT_MAX_LINES!==2000||n.DEFAULT_MAX_BYTES!==51200)throw Error("public defaults");
        \\ if(Object.keys(n).sort().join()!==Object.keys(s).sort().join())throw Error("six actual exports");
        \\ const shape=f=>[f.name,f.length,Object.hasOwn(f,"prototype"),Object.getPrototypeOf(f)===Function.prototype,Object.getOwnPropertyDescriptor(f,"prototype").writable];
        \\ for(const name of ["formatSize","truncateHead","truncateTail","truncateLine"]){
        \\   if(JSON.stringify(shape(n[name]))!==JSON.stringify(shape(s[name])))throw Error("ordinary shape "+name);
        \\ }
        \\ for(const f of [s.truncateHead,n.truncateHead]){
        \\   const one=f("text"),two=Reflect.construct(f,["text"],class Alternate{});
        \\   if(one===two||Object.getPrototypeOf(two)!==Object.prototype)throw Error("returned record identity");
        \\ }
        \\ for(const f of [s.formatSize,n.formatSize]){
        \\   class Alternate{};const value=Reflect.construct(f,[1],Alternate);
        \\   if(Object.getPrototypeOf(value)!==Alternate.prototype)throw Error("ordinary primitive constructor return");
        \\ }
        \\ return true;
        \\})()
    );
}
test "SDK public truncation actual frozen Source Unicode newline and independent limits" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try install(engine);
    try check(engine,
        \\(() => {
        \\ const cases=[
        \\  ["",undefined],["",{maxLines:0,maxBytes:0}],["",{maxLines:-1,maxBytes:0}],
        \\  ["a\n",undefined],["\n",undefined],["a\n\n",{maxLines:1}],["a\r\nb\r\n",{maxLines:1}],
        \\  ["a\nb\nc\n",{maxLines:2,maxBytes:100}],["a\nb\nc",{maxLines:2,maxBytes:3}],
        \\  ["first\nsecond",{maxLines:0,maxBytes:100}],["first\nsecond",{maxLines:1.5,maxBytes:100}],
        \\  ["é\n世界\n🌍",{maxBytes:7}],["é\n世界\n🌍",{maxBytes:3}],["long line",{maxBytes:0}],
        \\  ["🌍🌎",{maxBytes:5}],["🌍🌎",{maxBytes:3}],["line\n",{maxLines:NaN,maxBytes:Infinity}],
        \\  ["line\n",{maxLines:Infinity,maxBytes:NaN}],["one\ntwo",{maxLines:null,maxBytes:null}],
        \\  ["x",{maxLines:1,maxBytes:-1}],["x",null],["x",{maxLines:"1",maxBytes:"1"}]
        \\ ];
        \\ const outcome=(f,args)=>{try{return ["return",f(...args)]}catch(e){return ["throw",e.name,e.code,e.message]}};
        \\ for(const name of ["truncateHead","truncateTail"])for(let i=0;i<cases.length;i++){
        \\   const expected=JSON.stringify(outcome(publicTruncationSource[name],cases[i]));
        \\   const actual=JSON.stringify(outcome(publicTruncationNative[name],cases[i]));
        \\   if(actual!==expected)throw Error(name+" "+i+"\n"+expected+"\n"+actual);
        \\ }
        \\ const n=publicTruncationNative;
        \\ if(n.truncateHead("a\n").content!=="a\n")throw Error("fast path newline");
        \\ const first=n.truncateHead("long\nx",{maxBytes:2});
        \\ if(first.content!==""||!first.firstLineExceedsLimit||first.outputLines!==0)throw Error("whole first line rule");
        \\ const tail=n.truncateTail("🌍🌎",{maxBytes:5});
        \\ if(tail.content!=="🌎"||tail.outputBytes!==4||!tail.lastLinePartial)throw Error("UTF8 tail boundary");
        \\ for(const input of [-1,0,1023,1024,1536,1048576,NaN,Infinity,1n,2048n]){
        \\   if(JSON.stringify(outcome(n.formatSize,[input]))!==JSON.stringify(outcome(publicTruncationSource.formatSize,[input])))throw Error("formatSize");
        \\ }
        \\ for(const args of [["abc",undefined],["🌍x",1],["abc",0],["abc",-1],["abc",1.5],["abc",NaN],["abc",Infinity]]){
        \\   if(JSON.stringify(outcome(n.truncateLine,args))!==JSON.stringify(outcome(publicTruncationSource.truncateLine,args)))throw Error("UTF16 single line");
        \\ }
        \\ return true;
        \\})()
    );
}
test "SDK public truncation actual live Buffer string array and option coercion order" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try install(engine);
    try check(engine,
        \\(() => {
        \\ function observe(subject,name){
        \\   const trace=[], push=Array.prototype.push, saved=Object.getOwnPropertyDescriptor(globalThis,"Buffer"), original=Buffer;
        \\   const log=(...entry)=>push.call(trace,entry);
        \\   const descriptors={};for(const method of ["push","unshift","join"])descriptors[method]=Object.getOwnPropertyDescriptor(Array.prototype,method);
        \\   const lines=new Proxy(["é","world"],{get(t,k,r){log("lines get",String(k));return Reflect.get(t,k,r)}});
        \\   const content={
        \\     get length(){log("content length");return 7},
        \\     get split(){log("get split");return function(separator){log("split",this===content,separator);return lines}},
        \\     get endsWith(){log("get endsWith");return function(suffix){log("endsWith",this===content,suffix);return false}}
        \\   };
        \\   const buffer={
        \\     get byteLength(){log("get byteLength");return function(value,encoding){log("byteLength",this===buffer,value===content?"content":value,encoding);return value===content?8:original.byteLength(value,encoding)}},
        \\     get from(){log("get from");return function(value,encoding){log("from",this===buffer,value,encoding);return original.from(value,encoding)}}
        \\   };
        \\   const options={get maxLines(){log("get maxLines");return {valueOf(){log("coerce maxLines");return 1}}},get maxBytes(){log("get maxBytes");return {valueOf(){log("coerce maxBytes");return 3}}}};
        \\   try{
        \\     Object.defineProperty(globalThis,"Buffer",{configurable:true,get(){log("get Buffer");return buffer}});
        \\     for(const method of ["push","unshift","join"])Object.defineProperty(Array.prototype,method,{configurable:true,get(){log("array method",method);return function(...args){log("array call",method,...args);return descriptors[method].value.apply(this,args)}}});
        \\     const result=subject[name](content,options);
        \\     log("result",result.content,result.truncatedBy,result.outputLines,result.outputBytes,result.lastLinePartial);
        \\   }finally{
        \\     Object.defineProperty(globalThis,"Buffer",saved);
        \\     for(const method of ["push","unshift","join"])Object.defineProperty(Array.prototype,method,descriptors[method]);
        \\   }
        \\   return JSON.stringify(trace);
        \\ }
        \\ for(const name of ["truncateHead","truncateTail"]){
        \\   const expected=observe(publicTruncationSource,name),actual=observe(publicTruncationNative,name);
        \\   if(actual!==expected)throw Error(name+"\n"+expected+"\n"+actual);
        \\ }
        \\ return true;
        \\})()
    );
}
test "SDK public truncation actual tail keeps Source BigInt increment semantics on live buffers" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try install(engine);
    try check(engine,
        \\(() => {
        \\ function observe(subject){
        \\   const trace=[],saved=Object.getOwnPropertyDescriptor(globalThis,"Buffer");
        \\   const buffer={
        \\     get length(){trace.push("length");return 4n},
        \\     get 3(){trace.push("byte 3");return 128},
        \\     get slice(){trace.push("get slice");return function(start){trace.push(["slice",typeof start,String(start),this===buffer]);return {toString(encoding){trace.push(["toString",encoding]);return "suffix"}}}}
        \\   };
        \\   try{
        \\     globalThis.Buffer={byteLength(value,encoding){trace.push(["byteLength",value,encoding]);return value==="suffix"?0:10},from(value,encoding){trace.push(["from",value,encoding]);return buffer}};
        \\     const result=subject.truncateTail("long",{maxBytes:1n});
        \\     trace.push([result.content,result.outputBytes,result.lastLinePartial,typeof result.maxBytes]);
        \\   }finally{Object.defineProperty(globalThis,"Buffer",saved)}
        \\   return JSON.stringify(trace);
        \\ }
        \\ const expected=observe(publicTruncationSource),actual=observe(publicTruncationNative);
        \\ if(actual!==expected)throw Error(expected+"\n"+actual);
        \\ return true;
        \\})()
    );
}
test "SDK public truncation actual method temporaries retire before the next guest expression" {
    inline for (.{ false, true }) |use_native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try install(engine);
        try execute(engine, if (use_native) "globalThis.selectedTruncation=publicTruncationNative" else "globalThis.selectedTruncation=publicTruncationSource");
        try check(engine,
            \\(() => {
            \\ const saved=Object.getOwnPropertyDescriptor(globalThis,"Buffer");
            \\ let callable=()=>1;callable.holder=truncHooks.make(0);
            \\ let owner={holder:truncHooks.make(1)};
            \\ Object.defineProperty(owner,"byteLength",{get(){const value=callable;callable=undefined;return value}});
            \\ const content={get length(){if(truncHooks.count(0)!==1||truncHooks.count(1)!==1)throw Error("Buffer receiver/callee retained");return 0}};
            \\ try{
            \\   Object.defineProperty(globalThis,"Buffer",{configurable:true,get(){const value=owner;owner=undefined;return value}});
            \\   if(selectedTruncation.truncateHead(content).content!==content)throw Error("actual fast path");
            \\ }finally{Object.defineProperty(globalThis,"Buffer",saved)}
            \\ const fixedDescriptor=Object.getOwnPropertyDescriptor(Number.prototype,"toFixed");
            \\ const formatted={[Symbol.toPrimitive](hint){if(hint!=="string"||truncHooks.count(2)!==1)throw Error("toFixed callee retained");return "2.0"}};
            \\ let fixed=()=>formatted;fixed.holder=truncHooks.make(2);
            \\ try{
            \\   Object.defineProperty(Number.prototype,"toFixed",{configurable:true,get(){const value=fixed;fixed=undefined;return value}});
            \\   if(selectedTruncation.formatSize(2048)!=="2.0KB")throw Error("actual formatted value");
            \\ }finally{Object.defineProperty(Number.prototype,"toFixed",fixedDescriptor)}
            \\ let from=()=>({get length(){if(truncHooks.count(3)!==1)throw Error("from callee retained");return 4},3:0,slice(){return {toString(){return "tail"}}}});from.holder=truncHooks.make(3);
            \\ try{
            \\   globalThis.Buffer={byteLength(value){return value==="tail"?1:4},get from(){const value=from;from=undefined;return value}};
            \\   if(selectedTruncation.truncateTail("long",{maxBytes:1}).content!=="tail")throw Error("actual partial tail");
            \\ }finally{Object.defineProperty(globalThis,"Buffer",saved)}
            \\ for(let i=0;i<4;i++)if(truncHooks.count(i)!==1)throw Error("actual holder retirement "+i);
            \\ return true;
            \\})()
        );
    }
}
test "SDK public truncation same options getter private DATA remains an ordinary throw" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try install(engine);
    try check(engine,
        \\(() => {
        \\ let original,after=false,seen=false;
        \\ const options={get maxLines(){original=truncHooks.freshPrivateData();throw original},get maxBytes(){after=true;return 10}};
        \\ try{publicTruncationNative.truncateHead("text",options)}catch(reason){if(reason!==original)throw Error("ordinary DATA identity");seen=true}
        \\ if(!seen||after||!truncHooks.isUnmarkedPrivateData(original))throw Error("ordinary DATA boundary");
        \\ return true;
        \\})()
    );
}
test "SDK public truncation actual producer overrides prior private DATA before downstream code" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try install(engine);
    const hooks = try rawGlobal(engine, "truncHooks"); defer engine.freeValue(hooks);
    const record = c.JS_GetPropertyStr(engine.context, hooks, "record"); defer engine.freeValue(record);
    try execute(engine,
        \\globalThis.truncOptions={get maxLines(){
        \\ truncHooks.freshPrivateData();
        \\ try{truncHooks.raiseNativeFatal()}catch(error){truncHooks.record.guestReached=true}
        \\ truncHooks.record.guestReached=true;return 0;
        \\},get maxBytes(){truncHooks.record.guestReached=true;return 0}};
    );
    try std.testing.expectError(error.JavaScriptException, engine.eval("publicTruncationNative.truncateHead('text',truncOptions)", "actual-truncation-producer.js", c.JS_EVAL_TYPE_GLOBAL));
    try retirement.verifyRecordedActualNativeFatal(engine, record);
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
test "SDK public truncation actual callee retirement producer stops the next getter" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try install(engine);
    const hooks = try rawGlobal(engine, "truncHooks"); defer engine.freeValue(hooks);
    const record = c.JS_GetPropertyStr(engine.context, hooks, "record"); defer engine.freeValue(record);
    try execute(engine,
        \\let doomedMethod=()=>1;doomedMethod.holder=truncHooks.make(0);
        \\globalThis.Buffer={get byteLength(){const value=doomedMethod;doomedMethod=undefined;return value}};
        \\globalThis.truncContent={get length(){truncHooks.visit(2);return 0}};
        \\truncHooks.armFatal(0);
    );
    try std.testing.expectError(error.JavaScriptException, engine.eval("publicTruncationNative.truncateHead(truncContent)", "actual-truncation-retirement-producer.js", c.JS_EVAL_TYPE_GLOBAL));
    try retirement.verifyActualRetirementFatal(engine, record, 0);
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
test "SDK public truncation actual collection loop cancellation is current fatal" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try install(engine);
    const namespace = try rawGlobal(engine, "publicTruncationNative"); defer engine.freeValue(namespace);
    const function = try engine.checked(c.JS_GetPropertyStr(engine.context, namespace, "truncateHead")); defer engine.freeValue(function);
    const text = try engine.checked(c.JS_NewString(engine.context, "one\ntwo")); defer engine.freeValue(text);
    const options = try engine.eval("({maxLines:1,maxBytes:100})", "actual-truncation-cancel-options.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(options);
    var args = [_]c.JSValue{ text, options };
    engine.cancelled.store(true, .release);
    const outcome = engine.checked(c.JS_Call(engine.context, function, c.pi_js_undefined(), args.len, &args));
    engine.cancelled.store(false, .release);
    try std.testing.expectError(error.JavaScriptException, outcome);
    const reason = engine.captured_exception orelse return error.RequiredTruncationCancellation;
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}

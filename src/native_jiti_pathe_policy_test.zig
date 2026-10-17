//! Prepared exact public Pathe ownership/fatal controls. No authored original
//! answers, successful fake filesystem collaborator or shared policy edits.
const std=@import("std");
const em=@import("extensions/engine.zig");
const js=@import("extensions/native_js_values.zig");
const pathe=@import("extensions/native_pathe.zig");
const m=@import("extensions/native_mlly_values.zig");
const c=em.c;
fn install(engine:*em.Engine,name:[*:0]const u8,value:c.JSValue)!void{
    const global=c.JS_GetGlobalObject(engine.context);defer engine.freeValue(global);
    try js.define(engine,global,name,c.JS_DupValue(engine.context,value));
}
fn rawTag(context:?*c.JSContext,_:c.JSValue,_:c_int,_:[*c]c.JSValue)callconv(.c)c.JSValue{return em.Engine.fromContext(context.?).throwNativeOutOfMemory();}
fn setup(engine:*em.Engine)!void{
    const bindings=try pathe.create(engine);defer engine.freeValue(bindings);try install(engine,"ActualPathePolicy",bindings);
    try engine.bindFunction("PathePolicyRawTag",rawTag,0);
}
test "Pathe compares all six additional genuine original policy observations"{
    const expected=try std.Io.Dir.cwd().readFileAlloc(std.testing.io,"src/extensions/fixtures/jiti-pathe-policy-2.0.3.json",std.testing.allocator,.limited(1024*1024));defer std.testing.allocator.free(expected);
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();
    const bindings=try pathe.create(engine);defer engine.freeValue(bindings);const subject=try js.object(engine);defer engine.freeValue(subject);
    try js.define(engine,subject,"path",c.JS_DupValue(engine.context,bindings));try js.define(engine,subject,"utils",c.JS_DupValue(engine.context,bindings));try install(engine,"nativePathePolicySubject",subject);
    const terminated=try engine.gpa.dupeZ(u8,expected);defer engine.gpa.free(terminated);const original=try engine.checked(c.JS_ParseJSON(engine.context,terminated.ptr,expected.len,"actual-pathe-policy.json"));defer engine.freeValue(original);try install(engine,"originalPathePolicy",original);
    const value=try engine.evalModule(@embedFile("extensions/fixtures/jiti-pathe-policy-2.0.3.input.mjs")++
        \\if(nativePathePolicyObservation.count!==6||originalPathePolicy.count!==6)throw Error('full original policy census required');for(let index=0;index<6;index++)if(JSON.stringify(nativePathePolicyObservation.rows[index])!==JSON.stringify(originalPathePolicy.rows[index]))throw Error(JSON.stringify({index,actual:nativePathePolicyObservation.rows[index],original:originalPathePolicy.rows[index]}));
    ,"pathe-policy-original-six.mjs");engine.freeValue(value);
}
fn fatal(engine:*em.Engine)!void{
    const reason=engine.captured_exception orelse return error.MissingPathePolicyFatal;
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    const global=c.JS_GetGlobalObject(engine.context);defer engine.freeValue(global);
    const caught=try js.get(engine,global,"pathePolicyCaught");defer engine.freeValue(caught);try std.testing.expectEqual(@as(c_int,0),c.JS_ToBool(engine.context,caught));
}
fn gpaPublic(constructing:bool)!void{
    var failing=std.testing.FailingAllocator.init(std.testing.allocator,.{});
    const engine=try em.Engine.init(failing.allocator(),.{});defer engine.deinit();try setup(engine);
    const callback=try engine.eval(if(constructing)"(()=>{globalThis.pathePolicyCaught=false;try{new ActualPathePolicy.join('a','b')}catch(reason){globalThis.pathePolicyCaught=true}})" else "(()=>{globalThis.pathePolicyCaught=false;try{ActualPathePolicy.join('a','b')}catch(reason){globalThis.pathePolicyCaught=true}})","pathe-policy-gpa-setup.js",c.JS_EVAL_TYPE_GLOBAL);defer engine.freeValue(callback);
    // Everything needed to enter the real public function is prepared first.
    // Arm the actual Engine allocator only for call/construction, then capture
    // its completion after restoring allocator admission (no guest cleanup).
    failing.fail_index=failing.alloc_index;failing.resize_fail_index=failing.resize_index;
    const completion=c.JS_Call(engine.context,callback,c.pi_js_undefined(),0,null);
    defer engine.freeValue(completion);
    failing.fail_index=std.math.maxInt(usize);failing.resize_fail_index=std.math.maxInt(usize);
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectError(error.JavaScriptException,engine.checked(completion));try fatal(engine);
}
test "Pathe real public call direct GPA failure cannot enter guest catch"{try gpaPublic(false);}
test "Pathe real public construction GPA failure crosses complete owned exit"{try gpaPublic(true);}
test "Pathe ordinary public failures transfer the captured slot"{
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();try setup(engine);
    const value=try engine.evalModule(
        \\const descriptor=Object.getOwnPropertyDescriptor(String.prototype,'replace'),reason={ordinary:true};Object.defineProperty(String.prototype,'replace',{configurable:true,value:function(){throw reason}});for(let i=0;i<3;i++){let caught;try{ActualPathePolicy.normalize('owned')}catch(error){caught=error}if(caught!==reason)throw Error('ordinary public identity')}Object.defineProperty(String.prototype,'replace',descriptor);
    ,"pathe-policy-ordinary-slot.mjs");engine.freeValue(value);try std.testing.expect(engine.captured_exception==null);
}
const normal_setup=
    \\globalThis.PathePolicyArmNormal=function(kind){const original=Object.getOwnPropertyDescriptor(Array.prototype,'sort');Object.defineProperty(Array.prototype,'sort',{configurable:true,value:function(compare){let old;try{PathePolicyRawTag()}catch(reason){old=reason}globalThis.pathePolicyHistorical=old;const pair={[Symbol.iterator](){return{next(){return{done:false,value:'a'}},get return(){if(kind==='old-getter')throw old;if(kind==='fresh-getter')return PathePolicyRawTag();return function(){if(kind==='old-call')throw old;return PathePolicyRawTag()}}}}};return compare(pair,['b','/root'])}});return()=>Object.defineProperty(Array.prototype,'sort',original)};
;
test "Pathe normal destructuring close older getter and call remain ordinary through parent export"{
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();try setup(engine);
    const value=try engine.evalModule(normal_setup++
        \\for(const kind of ['old-getter','old-call']){const restore=PathePolicyArmNormal(kind);let caught;try{ActualPathePolicy.normalizeAliases({a:'/one',b:'/two'})}catch(reason){caught=reason}if(caught!==pathePolicyHistorical)throw Error('normal close ordinary historical identity');restore()}
    ,"pathe-policy-normal-close-ordinary.mjs");engine.freeValue(value);try std.testing.expect(engine.captured_exception==null);
}
test "Pathe normal destructuring close fresh getter and call retain fatal identity"{
    for([_][]const u8{"fresh-getter","fresh-call"})|kind|{
        const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();try setup(engine);
        const source=try std.fmt.allocPrint(engine.gpa,"{s}PathePolicyArmNormal('{s}');globalThis.pathePolicyCaught=false;try{{ActualPathePolicy.normalizeAliases({{a:'/one',b:'/two'}})}}catch{{globalThis.pathePolicyCaught=true}}",.{normal_setup,kind});defer engine.gpa.free(source);
        try std.testing.expectError(error.JavaScriptException,engine.evalModule(source,"pathe-policy-normal-close-fatal.mjs"));try fatal(engine);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context,engine.captured_exception.?,engine.native_allocation_exception.?));
    }
}
test "Pathe abrupt cleanup older getter and call cannot override ordinary primary"{
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();try setup(engine);
    const value=try engine.evalModule(
        \\const original=Object.getOwnPropertyDescriptor(Array.prototype,Symbol.iterator);for(const getter of [true,false]){const primary={ordinaryPrimary:true};let old;Object.defineProperty(Array.prototype,Symbol.iterator,{configurable:true,value:function(){return{next(){return{done:false,value:{toString(){try{PathePolicyRawTag()}catch(reason){old=reason}throw primary}}}},get return(){if(getter)throw old;return function(){throw old}}}}});let caught;try{ActualPathePolicy.join('owned')}catch(reason){caught=reason}if(caught!==primary)throw Error('abrupt primary replaced by historical cleanup');Object.defineProperty(Array.prototype,Symbol.iterator,original)}
    ,"pathe-policy-abrupt-old-cleanup.mjs");engine.freeValue(value);try std.testing.expect(engine.captured_exception==null);
}
test "Pathe actual exported constructor prototype getter retains fresh fatal identity"{
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();try setup(engine);
    try std.testing.expectError(error.JavaScriptException,engine.evalModule(
        \\globalThis.pathePolicyCaught=false;const target=new Proxy(function(){},{get(target,key,receiver){if(key==='prototype')return PathePolicyRawTag();return Reflect.get(target,key,receiver)}});try{Reflect.construct(ActualPathePolicy.join,['owned'],target)}catch{globalThis.pathePolicyCaught=true}
    ,"pathe-policy-constructor-prebody-fatal.mjs"));try fatal(engine);try std.testing.expect(c.JS_IsStrictEqual(engine.context,engine.captured_exception.?,engine.native_allocation_exception.?));
}
/// Real URL imports are required; no successful Node converter substitute.
/// Run four fresh-realm profiles: URL/Pathe outer x ordinary/fresh inner close.
pub fn verifyActualCrossNamespaceReentry(engine:*em.Engine,actual:m.Imports,pathe_outer:bool,fresh_inner:bool)!void{
    try setup(engine);const urls=try @import("extensions/native_mlly_urls.zig").create(engine,.{.file_url_to_path=actual.file_url_to_path,.path_to_file_url=actual.path_to_file_url});defer engine.freeValue(urls);try install(engine,"ActualMllyPolicyURLs",urls);
    const source=try std.fmt.allocPrint(engine.gpa,"{s}const restoreSort=PathePolicyArmNormal('{s}'),replace=Object.getOwnPropertyDescriptor(String.prototype,'replace');Object.defineProperty(String.prototype,'replace',{{configurable:true,value:function(){{if(String(this)==='outer')return ActualMllyPolicyURLs.fileURLToPath('inner');return ActualPathePolicy.normalizeAliases({{a:'/one',b:'/two'}})}}}});globalThis.pathePolicyCaught=false;let caught;try{{{s}}}catch(reason){{globalThis.pathePolicyCaught=true;caught=reason}}if(caught!==pathePolicyHistorical)throw Error('cross namespace ordinary identity');Object.defineProperty(String.prototype,'replace',replace);restoreSort();",.{normal_setup,if(fresh_inner)"fresh-call" else "old-call",if(pathe_outer)"ActualPathePolicy.normalize('outer')" else "ActualMllyPolicyURLs.fileURLToPath('inner')"});defer engine.gpa.free(source);
    if(fresh_inner){try std.testing.expectError(error.JavaScriptException,engine.evalModule(source,"pathe-mlly-cross-fatal.mjs"));try fatal(engine);try std.testing.expect(c.JS_IsStrictEqual(engine.context,engine.captured_exception.?,engine.native_allocation_exception.?));}else{const value=try engine.evalModule(source,"pathe-mlly-cross-ordinary.mjs");engine.freeValue(value);try std.testing.expect(engine.captured_exception==null);}
}

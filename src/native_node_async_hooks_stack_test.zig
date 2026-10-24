//! Genuine shared Environment views and exact selected original JS stack bodies.
//! No hook-emitter, native exit policy or public async_hooks assembly is qualified.
const std = @import("std");
const support = @import("native_node_async_hooks_stack_test_support.zig");
const a = support.a;
const c = support.c;
const Fixture = support.Fixture;

test "native async stack selected declarations retain metadata and native clear identity" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(()=>{const names=['newAsyncId','getDefaultTriggerAsyncId','clearDefaultTriggerAsyncId',
        \\ 'enabledHooksExist','initHooksExist','afterHooksExist','destroyHooksExist',
        \\ 'hasAsyncIdStack','pushAsyncContext','popAsyncContext','executionAsyncId','triggerAsyncId'];
        \\ for(const n of names){const fn=S[n],ref=R[n];
        \\ if(fn.name!==ref.name||fn.length!==ref.length||Object.getPrototypeOf(fn)!==Function.prototype||
        \\ !Object.hasOwn(fn,'prototype'))return false;
        \\ const d=Object.getOwnPropertyDescriptor(S,n);if(!d.writable||!d.enumerable||!d.configurable)return false}
        \\ return Object.keys(S).length===13&&S.clearAsyncIdStack===stackBinding.clearAsyncIdStack&&
        \\ S.clearAsyncIdStack===R.clearAsyncIdStack&&!('emitAfter' in S)})()
    );
}
test "native async stack borrows the exact Environment views and acquired resource array" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    const again = try f.env().acquireExecutionAsyncResources();
    defer f.engine.freeValue(again);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, again, f.env().js_resources.?));
    try f.check("stackFields===stackBinding.async_hook_fields&&stackUid===stackBinding.async_id_fields&&stackResources===stackBinding.execution_async_resources");
    try f.run("stackUid[0]=31;stackUid[1]=17;stackUid[2]=400;stackFields[2]=3;");
    try std.testing.expectEqual(@as(f64, 31), f.env().executionAsyncId());
    try std.testing.expectEqual(@as(f64, 17), f.env().triggerAsyncId());
    try std.testing.expectEqual(@as(u32, 3), f.env().field(.after).*);
    try f.check("S.executionAsyncId()===31&&S.triggerAsyncId()===17&&S.afterHooksExist()");
}
test "native async stack prefix counter matches original numbers signed zero and NaN" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(()=>{for(const start of [1,0,-0,-4,1.5,NaN,Infinity,-Infinity]){
        \\ stackUid[2]=start;const actual=S.newAsyncId(),stored=stackUid[2];
        \\ stackUid[2]=start;const expected=R.newAsyncId();
        \\ if(!Object.is(actual,expected)||!Object.is(stored,stackUid[2]))return false}
        \\ return true})()
    );
}
test "native async stack default trigger follows original negative test and preserves zero" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(()=>{stackUid[0]=88;for(const value of [-4,-1,-0,0,12,NaN,Infinity]){
        \\ stackUid[3]=value;if(!Object.is(S.getDefaultTriggerAsyncId(),R.getDefaultTriggerAsyncId()))return false}
        \\ return S.clearDefaultTriggerAsyncId()===undefined&&stackUid[3]===-1&&S.getDefaultTriggerAsyncId()===88})()
    );
}
test "native async stack hook predicates read original independent live counter cells" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(()=>{const cases=[['enabledHooksExist',6],['initHooksExist',0],['afterHooksExist',2],
        \\ ['destroyHooksExist',3],['hasAsyncIdStack',7]];
        \\ for(const [name,index]of cases){for(const n of [0,1,0xffffffff]){
        \\ stackFields[index]=n;if(S[name]()!==R[name]()||S[name]()!==(n>0))return false}stackFields[index]=0}
        \\ return true})()
    );
}
test "native async stack fast push commits actual backing and resource before returning undefined" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run("stackUid[0]=9;stackUid[1]=4;globalThis.resource={tag:'actual'};globalThis.pushResult=S.pushAsyncContext(22,9,resource);");
    try f.check("pushResult===undefined&&stackFields[7]===1&&stackUid[0]===22&&stackUid[1]===9&&originalStackView[0]===9&&originalStackView[1]===4&&stackResources[0]===resource");
    try std.testing.expectEqual(@as(usize, 0), f.native_push_count);
    try std.testing.expectEqual(@as(f64, 22), f.env().executionAsyncId());
}
test "native async stack nested fast pop returns remaining stack boolean and restores exact pairs" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(()=>{S.pushAsyncContext(2,0,{tag:1});S.pushAsyncContext(3,2,{tag:2});
        \\ if(S.popAsyncContext(3)!==true||stackFields[7]!==1||stackUid[0]!==2||stackUid[1]!==0||stackResources.length!==1)return false;
        \\ return S.popAsyncContext(2)===false&&stackFields[7]===0&&stackUid[0]===0&&stackResources.length===0})()
    );
    try std.testing.expectEqual(@as(usize, 0), f.native_pop_count);
}
test "native async stack empty pop does not resolve stack property or resource pop" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\Object.defineProperty(stackBinding,'async_ids_stack',{get(){throw Error('unselected stack get')},configurable:true});
        \\Object.defineProperty(stackResources,'pop',{get(){throw Error('unselected resource get')},configurable:true});
    );
    try f.check("S.popAsyncContext({})===false&&stackFields[7]===0");
    try std.testing.expectEqual(@as(usize, 0), f.native_pop_count);
}
test "native async stack pop calls live resource method after IDs and before stack length" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\S.pushAsyncContext(12,5,{});
        \\stackResources.pop=function(){stackTrace.push([this===stackResources,arguments.length,stackUid[0],stackUid[1],stackFields[7]]);return Array.prototype.pop.call(this)};
    );
    try f.check("S.popAsyncContext(12)===false&&JSON.stringify(stackTrace)==='[[true,0,0,0,1]]'&&stackFields[7]===0");
}
test "native async stack pop resolves two live stack values in original assignment order" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\S.pushAsyncContext(12,5,{});globalThis.stackGets=0;
        \\Object.defineProperty(stackBinding,'async_ids_stack',{configurable:true,get(){
        \\ stackTrace.push([++stackGets,stackUid[0],stackUid[1],stackFields[7]]);
        \\ return stackGets===1?[41,42]:[51,52]}});
    );
    try f.check("S.popAsyncContext(12)===false&&stackUid[0]===41&&stackUid[1]===52&&JSON.stringify(stackTrace)==='[[1,12,5,1],[2,41,5,1]]'");
}
test "native async stack pop getter exception preserves reason and skips length commit" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\S.pushAsyncContext(12,5,{});globalThis.stackReason={};
        \\Object.defineProperty(stackResources,'pop',{get(){throw stackReason},configurable:true});
    );
    try f.check("(()=>{try{S.popAsyncContext(12)}catch(e){return e===stackReason&&stackUid[0]===0&&stackUid[1]===0&&stackFields[7]===1&&stackResources.length===1}return false})()");
}
test "native async stack ordinary throwing pop retains its mutations without committing stack length" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\S.pushAsyncContext(12,5,{});globalThis.stackReason={};
        \\stackResources.pop=function(){this.length=0;throw stackReason};
    );
    try f.check("(()=>{try{S.popAsyncContext(12)}catch(e){return e===stackReason&&stackUid[0]===0&&stackFields[7]===1&&stackResources.length===0}return false})()");
}
test "native async stack noncallable resource pop uses actual VM TypeError" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run("S.pushAsyncContext(12,5,{});stackResources.pop=17;");
    try f.check("(()=>{try{S.popAsyncContext(12)}catch(e){return e instanceof TypeError&&stackFields[7]===1&&stackUid[0]===0}return false})()");
}
test "native async stack mismatch routes to captured native corruption operation without live stack reads" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\S.pushAsyncContext(12,5,{});
        \\Object.defineProperty(stackBinding,'async_ids_stack',{get(){throw Error('unselected fast stack')},configurable:true});
    );
    try f.check("(()=>{try{S.popAsyncContext(11)}catch(e){return String(e).includes('UnselectedActualCorruptedStackExit')&&stackFields[7]===1&&stackUid[0]===12}return false})()");
    try std.testing.expectEqual(@as(usize, 1), f.native_pop_count);
    try std.testing.expectEqual(@as(usize, 1), f.corruption_count);
    try std.testing.expectEqual(@as(f64, 11), f.expected_corruption_id);
    try std.testing.expect(f.native_receivers_undefined);
}
test "native async stack disabled check skips mismatch fallback and uses original fast path" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run("S.pushAsyncContext(12,5,{});stackFields[6]=0;");
    try f.check("S.popAsyncContext(999)===false&&stackUid[0]===0&&stackFields[7]===0");
    try std.testing.expectEqual(@as(usize, 0), f.native_pop_count);
}
test "native async stack resource write precedes condition and preserves lexical offset across reentry" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\Object.defineProperty(stackResources,'0',{configurable:true,set(v){stackTrace.push(['resource',v.tag,stackFields[7]]);stackFields[7]=4}});
        \\Object.defineProperty(stackBinding,'async_ids_stack',{configurable:true,get(){stackTrace.push(['stack',stackFields[7]]);return originalStackView}});
        \\S.pushAsyncContext(9,3,{tag:'real'});
    );
    try f.check("JSON.stringify(stackTrace)==='[[\"resource\",\"real\",0],[\"stack\",4],[\"stack\",4],[\"stack\",4]]'&&stackFields[7]===5&&stackUid[0]===9&&originalStackView[0]===0");
}
test "native async stack resource setter failure precedes every stack read and mutation" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\globalThis.stackReason={};
        \\Object.defineProperty(stackResources,'0',{configurable:true,set(){throw stackReason}});
        \\Object.defineProperty(stackBinding,'async_ids_stack',{configurable:true,get(){throw Error('unselected stack')}});
    );
    try f.check("(()=>{try{S.pushAsyncContext(9,3,{})}catch(e){return e===stackReason&&stackFields[7]===0&&stackUid[0]===0}return false})()");
    try std.testing.expectEqual(@as(usize, 0), f.native_push_count);
}
test "native async stack push resolves condition and both assignment bases independently" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\stackUid[0]=41;stackUid[1]=42;globalThis.stackGets=0;
        \\Object.defineProperty(stackBinding,'async_ids_stack',{configurable:true,get(){
        \\ const which=++stackGets;stackTrace.push(['get',which]);
        \\ if(which===1)return {length:32};
        \\ return new Proxy({}, {set(t,k,v){stackTrace.push(['set',which,k,v,stackFields[7]]);return true}})}});
        \\S.pushAsyncContext(9,3,{});
    );
    try f.check("JSON.stringify(stackTrace)==='[[\"get\",1],[\"get\",2],[\"set\",2,\"0\",41,0],[\"get\",3],[\"set\",3,\"1\",42,0]]'&&stackFields[7]===1&&stackUid[0]===9&&stackUid[1]===3");
}
test "native async stack second stack setter exception preserves only preceding source effects" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\globalThis.stackReason={};globalThis.stackGets=0;stackUid[0]=41;stackUid[1]=42;
        \\Object.defineProperty(stackBinding,'async_ids_stack',{configurable:true,get(){
        \\ if(++stackGets===1)return {length:32};
        \\ return new Proxy({}, {set(t,k,v){stackTrace.push([k,v]);if(k==='1')throw stackReason;return true}})}});
    );
    try f.check("(()=>{try{S.pushAsyncContext(9,3,{})}catch(e){return e===stackReason&&JSON.stringify(stackTrace)==='[[\"0\",41],[\"1\",42]]'&&stackFields[7]===0&&stackUid[0]===41&&stackResources.length===1}return false})()");
}
test "native async stack dynamic length coercion selects real fallback with original receiver" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\stackBinding.async_ids_stack={get length(){stackTrace.push('length');return {valueOf(){stackTrace.push('coerce');return 0}}}};
        \\S.pushAsyncContext(9,3,{});
    );
    try f.check("JSON.stringify(stackTrace)==='[\"length\",\"coerce\"]'&&stackFields[7]===1&&stackUid[0]===9&&stackResources.length===1");
    try std.testing.expectEqual(@as(usize, 1), f.native_push_count);
    try std.testing.expect(f.native_receivers_undefined);
}
test "native async stack overflow grows actual Environment backing while old view stays retained" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run("for(let i=0;i<17;i++)S.pushAsyncContext(i+2,i,{index:i});");
    try std.testing.expectEqual(@as(usize, 1), f.native_push_count);
    try std.testing.expectEqual(@as(usize, 96), f.env().ids.data.len);
    try f.check("stackFields[7]===17&&stackUid[0]===18&&stackResources.length===17&&originalStackView.length===32&&stackBinding.async_ids_stack.length===96&&originalStackView!==stackBinding.async_ids_stack&&stackBinding.async_ids_stack[32]===17");
    try f.check("(()=>{for(let id=18;id>=2;id--){if(S.popAsyncContext(id)!==(id>2))return false}return stackFields[7]===0&&stackResources.length===0&&stackUid[0]===0})()");
}
test "native async stack captured native functions survive later binding replacement" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\const unexpected=function(){throw Error('replaced native callback')};
        \\stackBinding.pushAsyncContext=unexpected;stackBinding.popAsyncContext=unexpected;stackBinding.clearAsyncIdStack=unexpected;
        \\for(let i=0;i<17;i++)S.pushAsyncContext(i+2,i,{});
    );
    try std.testing.expectEqual(@as(usize, 1), f.native_push_count);
    try f.check("S.clearAsyncIdStack()===undefined&&stackFields[7]===0&&stackUid[0]===0&&stackResources.length===0&&S.clearAsyncIdStack!==stackBinding.clearAsyncIdStack");
    try std.testing.expectEqual(@as(usize, 1), f.native_clear_count);
}
test "native async stack captured arrays remain original when binding properties are reassigned" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\stackBinding.async_hook_fields=new Uint32Array(9);
        \\stackBinding.async_id_fields=new Float64Array(4);
        \\stackBinding.execution_async_resources=[];
        \\S.pushAsyncContext(15,6,{});
    );
    try f.check("stackFields[7]===1&&stackUid[0]===15&&stackResources.length===1&&stackBinding.async_hook_fields[7]===0&&stackBinding.async_id_fields[0]===0&&stackBinding.execution_async_resources.length===0");
}
test "native async stack lexical pop offset wins over reentrant resource mutation" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\S.pushAsyncContext(7,3,{});
        \\stackResources.pop=function(){stackFields[7]=9;return undefined};
    );
    try f.check("S.popAsyncContext(7)===false&&stackFields[7]===0&&stackResources.length===1");
}
test "native async stack original source differential matrix preserves full shared state" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.check(
        \\(()=>{function exercise(api){
        \\ stackFields.fill(0);stackFields[6]=1;stackUid.fill(0);stackUid[2]=1;stackUid[3]=-1;
        \\ stackResources.length=0;stackBinding.async_ids_stack.fill(0);
        \\ const results=[api.executionAsyncId(),api.triggerAsyncId(),api.newAsyncId(),api.getDefaultTriggerAsyncId()];
        \\ for(let i=0;i<6;i++)results.push(api.pushAsyncContext(i+3,i,{index:i}));
        \\ for(let i=8;i>=3;i--)results.push(api.popAsyncContext(i));
        \\ api.clearDefaultTriggerAsyncId();results.push(api.hasAsyncIdStack(),api.afterHooksExist());
        \\ return JSON.stringify([results,Array.from(stackFields),Array.from(stackUid),Array.from(stackBinding.async_ids_stack),stackResources])}
        \\ return exercise(S)===exercise(R)})()
    );
}
test "native async stack private acquisition is cached and exact binding conflict is rejected" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    c.JS_RunGC(f.engine.runtime);
    const again = try support.owner.create(f.engine, f.env(), f.binding);
    defer f.engine.freeValue(again);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, again, f.exported));
    const different = try f.engine.checked(c.JS_NewObject(f.engine.context));
    defer f.engine.freeValue(different);
    try std.testing.expectError(error.ActualAsyncIdStackInputsConflict,
        support.owner.create(f.engine, f.env(), different));
    try f.balanced();
}
test "native async stack cold acquisition rejects copied arrays rather than accepting fake backing" {
    var f: Fixture = undefined; try f.init(false); defer f.deinit();
    try f.run("stackBinding.async_id_fields=new Float64Array(stackUid);");
    try std.testing.expectError(error.ActualAsyncWrapSharedViewsRequired,
        support.owner.create(f.engine, f.env(), f.binding));
    try std.testing.expect(!f.engine.native_module_values.contains(support.owner_key));
    try f.balanced();
}
test "native async stack cold binding getters preserve original capture read order and reason" {
    var f: Fixture = undefined; try f.init(false); defer f.deinit();
    try f.run(
        \\globalThis.stackReason={};
        \\for(const name of ['async_hook_fields','async_id_fields','execution_async_resources','pushAsyncContext','popAsyncContext','clearAsyncIdStack']){
        \\ const value=stackBinding[name];Object.defineProperty(stackBinding,name,{configurable:true,get(){
        \\ stackTrace.push(name);if(name==='popAsyncContext')throw stackReason;return value}})}
    );
    try std.testing.expectError(error.JavaScriptException,
        support.owner.create(f.engine, f.env(), f.binding));
    const reason = try f.reason(); defer f.engine.freeValue(reason);
    try f.publish("observedStackReason", reason);
    try f.check("observedStackReason===stackReason&&stackTrace.join('|')==='async_hook_fields|async_id_fields|execution_async_resources|pushAsyncContext|popAsyncContext'");
    try std.testing.expect(!f.engine.native_module_values.contains(support.owner_key));
    try f.balanced();
}
test "native async stack retained callable keeps charged owner after cache removal and GC" {
    var f: Fixture = undefined; try f.init(false); defer f.deinit();
    const baseline = c.pi_js_native_memory_used(f.engine.native_memory_owner);
    try f.install();
    try f.run("globalThis.retainedStack=S.newAsyncId;delete globalThis.S;stackDropOwner();");
    f.engine.freeValue(f.exported); f.exported = c.pi_js_undefined();
    c.JS_RunGC(f.engine.runtime);
    try std.testing.expect(!f.engine.native_module_values.contains(support.owner_key));
    try std.testing.expect(c.pi_js_native_memory_used(f.engine.native_memory_owner) > baseline);
    try f.check("retainedStack()===2&&stackUid[2]===2");
    try f.run("delete globalThis.retainedStack;");
    c.JS_RunGC(f.engine.runtime);
    try std.testing.expectEqual(baseline, c.pi_js_native_memory_used(f.engine.native_memory_owner));
    try f.balanced();
}
test "native async stack pending cold entry wins before allocator failure and publication" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var f: Fixture = undefined; try f.initUsing(failing.allocator(), false); defer f.deinit();
    const original = try f.engine.checked(c.JS_NewError(f.engine.context));
    defer f.engine.freeValue(original);
    _ = c.JS_Throw(f.engine.context, a.duplicate(f.engine, original));
    const index = failing.alloc_index; failing.fail_index = index;
    const result = support.owner.create(f.engine, f.env(), f.binding);
    failing.fail_index = std.math.maxInt(usize);
    try std.testing.expectError(error.JavaScriptException, result);
    try std.testing.expectEqual(index, failing.alloc_index);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, original, f.engine.captured_exception.?));
    try std.testing.expect(!f.engine.native_module_values.contains(support.owner_key));
    try f.balanced();
}
test "native async stack actual cold allocation failure remains fatal and unpublished" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var f: Fixture = undefined; try f.initUsing(failing.allocator(), false); defer f.deinit();
    failing.fail_index = failing.alloc_index;
    const result = support.owner.create(f.engine, f.env(), f.binding);
    failing.fail_index = std.math.maxInt(usize);
    try std.testing.expectError(error.JavaScriptException, result);
    const observed = try f.reason(); defer f.engine.freeValue(observed);
    try std.testing.expect(c.JS_IsUncatchableError(observed));
    try std.testing.expect(!f.engine.native_module_values.contains(support.owner_key));
    try f.balanced();
}
test "native async stack actual fatal pop cannot be swallowed or commit later stack length" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.run(
        \\S.pushAsyncContext(12,5,{});globalThis.stackCaught=false;globalThis.stackReturned=false;
        \\stackResources.pop=function(){stackNativeFatal();return undefined};
    );
    try std.testing.expectError(error.JavaScriptException, f.engine.eval(
        "try{S.popAsyncContext(12);stackReturned=true}catch(e){stackCaught=true}",
        "actual-async-stack-fatal.js", c.JS_EVAL_TYPE_GLOBAL));
    const observed = try f.reason(); defer f.engine.freeValue(observed);
    try std.testing.expect(c.JS_IsUncatchableError(observed));
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, observed, f.first_fatal));
    try f.check("stackCaught===false&&stackReturned===false&&stackFields[7]===1&&stackUid[0]===0&&stackUid[1]===0");
    try f.balanced();
}
test "native async stack returned flagged DATA does not become a pending fatal" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    const flagged = try f.engine.checked(c.JS_NewError(f.engine.context));
    defer f.engine.freeValue(flagged);
    c.JS_SetUncatchableError(f.engine.context, flagged);
    try f.publish("stackFlaggedData", flagged);
    try f.run("S.pushAsyncContext(12,5,{});stackResources.pop=function(){return stackFlaggedData};");
    try f.check("S.popAsyncContext(12)===false&&stackFields[7]===0&&stackResources.length===1");
    try f.balanced();
}
test "native async stack closed Environment rejects later owner calls while retained views stay valid" {
    var f: Fixture = undefined; try f.init(true); defer f.deinit();
    try f.closeEnvironment();
    c.JS_RunGC(f.engine.runtime);
    try f.check("(()=>{try{S.executionAsyncId()}catch(e){return String(e).includes('NativeNodeEnvironmentClosed')&&stackUid instanceof Float64Array&&stackUid[0]===0}return false})()");
    try f.balanced();
}

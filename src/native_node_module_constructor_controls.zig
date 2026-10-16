//! Prepared real Module constructor/paths/cache controls. Inputs are actual
//! installed namespaces/options; no legacy cache record is relabelled.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const module = @import("extensions/native_node_module_constructor.zig");
fn install(engine: *v.em.Engine, name: [*:0]const u8, value: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try v.js.define(engine, global, name, c.JS_DupValue(engine.context, value));
}
pub fn verifyConstructorAndPrivateParents(engine: *v.em.Engine, actual_inputs: module.Inputs) !void {
    const graph = try module.create(engine, actual_inputs); defer engine.freeValue(graph.module_constructor); defer engine.freeValue(graph.namespace_exports);
    const again = try module.create(engine, actual_inputs); defer engine.freeValue(again.module_constructor); defer engine.freeValue(again.namespace_exports);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, graph.module_constructor, again.module_constructor));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, graph.namespace_exports, again.namespace_exports));
    try install(engine, "ActualModule", graph.module_constructor);
    const result = try engine.evalModule(
        \\const Module=ActualModule,parent=new Module('parent/file.js'),child=new Module('child/file.js',parent);
        \\if(!(child instanceof Module)||Object.getPrototypeOf(child)!==Module.prototype||child.constructor!==Module||Module.Module!==Module||Module.length!==0)throw Error('real Module identity');
        \\if(Object.keys(child).join()!=='id,path,exports,filename,loaded,children'||child.filename!==null||child.loaded!==false||child.children.length)throw Error('Source constructor fields/order');
        \\if(child.parent!==parent||parent.children.length!==1||parent.children[0]!==child||Object.hasOwn(child,'parent')||Object.getOwnPropertySymbols(child).length)throw Error('private parents/children');
        \\const second=new Module('second');child.parent=second;if(child.parent!==second||second.children.length||parent.children[0]!==child)throw Error('parent setter must not update children');
        \\const fresh=new Module;if(fresh.id!==''||fresh.exports===child.exports||fresh.children===child.children||fresh.parent!==undefined)throw Error('fresh/default construction');
        \\const inherited=Object.create(child),getter=Object.getOwnPropertyDescriptor(Module.prototype,'parent').get;if(getter.call(inherited)!==undefined)throw Error('private state inherited');
        \\const d=Object.getOwnPropertyDescriptor(Module.prototype,'constructor'),p=Object.getOwnPropertyDescriptor(Module.prototype,'parent');
        \\if(d.configurable||d.enumerable||d.set!==undefined||d.get.call({})!==Module||p.configurable||p.enumerable||p.get.name!=='deprecated'||p.get.length!==0||p.set.length!==1)throw Error('prototype descriptors');
        \\class Derived extends Module{}const derived=new Derived('derived');if(!(derived instanceof Module)||!(derived instanceof Derived)||Object.getPrototypeOf(derived)!==Derived.prototype)throw Error('new-target prototype');
        \\export const parentForNativeCheck=parent,childForNativeCheck=child;
    , "node-module-constructor-private-parents.mjs");
    defer engine.freeValue(result);
    const parent = try v.js.get(engine, result, "parentForNativeCheck"); defer engine.freeValue(parent);
    const child = try v.js.get(engine, result, "childForNativeCheck"); defer engine.freeValue(child);
    const last = try module.lastParent(engine, graph.module_constructor, child); defer engine.freeValue(last);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, parent, last));
}
pub fn verifyEffectsAndPrimordials(engine: *v.em.Engine, actual_inputs: module.Inputs) !void {
    const graph = try module.create(engine, actual_inputs); defer engine.freeValue(graph.module_constructor); defer engine.freeValue(graph.namespace_exports);
    try install(engine, "ActualModule", graph.module_constructor);
    try install(engine, "ActualNodePath", actual_inputs.paths);
    const result = try engine.evalModule(
        \\const Module=ActualModule,path=ActualNodePath,original=Object.getOwnPropertyDescriptor(path,'dirname'),trace=[];
        \\const receiver=new Proxy(Object.create(Module.prototype),{set(target,key,value,self){trace.push('set:'+String(key));return Reflect.set(target,key,value,self)},defineProperty(target,key,d){trace.push('define:'+String(key));return Reflect.defineProperty(target,key,d)}});
        \\const parent={get children(){trace.push('children');return[]}};
        \\Object.defineProperty(path,'dirname',{configurable:true,get(){trace.push('dirname-get');return function(id){trace.push(this===path?'dirname-this':'wrong-this');return original.value.call(this,id)}}});
        \\try{Module.call(receiver,'folder/file.js',parent)}finally{Object.defineProperty(path,'dirname',original)}
        \\if(trace.join()!=='set:id,define:id,dirname-get,dirname-this,set:path,define:path,define:exports,children,set:filename,define:filename,set:loaded,define:loaded,set:children,define:children')throw Error('constructor Source effects/private traps');
        \\const exportsDescriptor=Object.getOwnPropertyDescriptor(Module.prototype,'exports');let setterCalls=0;Object.defineProperty(Module.prototype,'exports',{configurable:true,set(){setterCalls++}});
        \\try{const item=new Module('own');if(setterCalls||!Object.hasOwn(item,'exports'))throw Error('exports own define')}finally{if(exportsDescriptor)Object.defineProperty(Module.prototype,'exports',exportsDescriptor);else delete Module.prototype.exports}
        \\const push=Array.prototype.push,charCode=String.prototype.charCodeAt,slice=String.prototype.slice;
        \\try{Array.prototype.push=String.prototype.charCodeAt=String.prototype.slice=()=>{throw Error('polluted primordial')};const p=new Module('p'),child=new Module('c',p);if(p.children[0]!==child||Module._nodeModulePaths('node_modules/package').length===0)throw Error('captured primordials')}finally{Array.prototype.push=push;String.prototype.charCodeAt=charCode;String.prototype.slice=slice}
        \\export const passed=true;
    , "node-module-constructor-effects-primordials.mjs");
    defer engine.freeValue(result);
}
pub fn verifyActualPathReference(engine: *v.em.Engine, actual_inputs: module.Inputs, actual_from: c.JSValue, accepted_source_paths: c.JSValue) !void {
    const graph = try module.create(engine, actual_inputs); defer engine.freeValue(graph.module_constructor); defer engine.freeValue(graph.namespace_exports);
    const paths = try v.js.invoke(engine, graph.module_constructor, "_nodeModulePaths", &.{actual_from}); defer engine.freeValue(paths);
    try install(engine, "ActualLookupPaths", paths); try install(engine, "SourceLookupPaths", accepted_source_paths);
    const result = try engine.evalModule(
        \\if(JSON.stringify(ActualLookupPaths)!==JSON.stringify(SourceLookupPaths))throw Error('actual Node path reference');export const passed=true;
    , "node-module-paths-actual-reference.mjs");
    defer engine.freeValue(result);
}
pub fn verifyActualCachePublication(engine: *v.em.Engine, actual_inputs: module.Inputs, owned_filename: c.JSValue) !void {
    const graph = try module.create(engine, actual_inputs); defer engine.freeValue(graph.module_constructor); defer engine.freeValue(graph.namespace_exports);
    const record = try engine.checked(c.JS_CallConstructor(engine.context, graph.module_constructor, 1, @constCast(&owned_filename))); defer engine.freeValue(record);
    const exports = try v.js.get(engine, record, "exports"); defer engine.freeValue(exports);
    try module.publish(engine, graph.module_constructor, owned_filename, record);
    const cached = try v.js.getKey(engine, engine.commonjs_cache, owned_filename); defer engine.freeValue(cached);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, record, cached));
    const ctor = try v.js.get(engine, cached, "constructor"); defer engine.freeValue(ctor);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, ctor, graph.module_constructor));
    const retained_exports = try v.js.get(engine, cached, "exports"); defer engine.freeValue(retained_exports);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, exports, retained_exports));
    const require = try v.js.call(engine, actual_inputs.create_require, c.pi_js_undefined(), &.{owned_filename}); defer engine.freeValue(require);
    const require_cache = try v.js.get(engine, require, "cache"); defer engine.freeValue(require_cache);
    const module_cache = try v.js.get(engine, graph.module_constructor, "_cache"); defer engine.freeValue(module_cache);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, require_cache, module_cache));
    // No legacy CommonJS load is invoked: real loader/prototype integration is
    // a separate gate, rather than treating plain records as Module instances.
}
pub fn verifyExactThrownReasons(engine: *v.em.Engine, actual_inputs: module.Inputs) !void {
    const graph = try module.create(engine, actual_inputs); defer engine.freeValue(graph.module_constructor); defer engine.freeValue(graph.namespace_exports);
    try install(engine, "ActualModule", graph.module_constructor); try install(engine, "ActualNodePath", actual_inputs.paths);
    const result = try engine.evalModule(
        \\const Module=ActualModule,path=ActualNodePath,marker={},original=Object.getOwnPropertyDescriptor(path,'dirname');
        \\Object.defineProperty(path,'dirname',{configurable:true,get(){throw marker}});const early={};let caught;
        \\try{Module.call(early,'x')}catch(e){caught=e}finally{Object.defineProperty(path,'dirname',original)}
        \\if(caught!==marker||Object.keys(early).join()!=='id')throw Error('dirname reason/partial receiver');
        \\const late={},parent={get children(){throw marker}};caught=undefined;try{Module.call(late,'x',parent)}catch(e){caught=e}
        \\if(caught!==marker||late.parent!==parent||Object.keys(late).join()!=='id,path,exports')throw Error('parent reason/private state/order');
        \\const trace=[],receiver=new Proxy({},{set(t,k,v,r){trace.push('set:'+String(k));return Reflect.set(t,k,v,r)},defineProperty(t,k,d){trace.push('define:'+String(k));if(k==='exports')throw marker;return Reflect.defineProperty(t,k,d)}});
        \\caught=undefined;try{Module.call(receiver,'x')}catch(e){caught=e}if(caught!==marker||trace.join()!=='set:id,define:id,set:path,define:path,define:exports')throw Error('own define exact reason');
        \\export const passed=true;
    , "node-module-exact-thrown-reasons.mjs");
    defer engine.freeValue(result);
}
/// Fresh Engine, actual --pending-deprecation enabled / --no-deprecation off.
/// This control deliberately replaces only the guest-visible emitWarning and
/// restores it. Separate actual host-option reference runs remain required.
pub fn verifyPendingDeprecation(engine: *v.em.Engine, actual_inputs: module.Inputs) !void {
    try std.testing.expect(actual_inputs.pending_deprecation and !actual_inputs.no_deprecation);
    const graph = try module.create(engine, actual_inputs); defer engine.freeValue(graph.module_constructor); defer engine.freeValue(graph.namespace_exports);
    try install(engine, "ActualModule", graph.module_constructor); try install(engine, "ActualProcess", actual_inputs.process);
    const result = try engine.evalModule(
        \\const Module=ActualModule,process=ActualProcess,descriptor=Object.getOwnPropertyDescriptor(process,'emitWarning'),marker={},trace=[];
        \\const parent=Object.getOwnPropertyDescriptor(Module.prototype,'parent'),a=new Module('a'),b=new Module('b');
        \\Object.defineProperty(process,'emitWarning',{configurable:true,writable:true,value:function(message,type,code,ctor){'use strict';trace.push({message,type,code,same:ctor===parent.get,receiver:this});throw marker}});
        \\try{let caught;try{void a.parent}catch(e){caught=e}if(caught!==marker||trace.length!==1||trace[0].receiver!==undefined||!trace[0].same||trace[0].code!=='DEP0144')throw Error('warning raw reason/receiver');
        \\if(a.parent!==undefined||trace.length!==1)throw Error('getter warned before throwing');
        \\Object.defineProperty(process,'emitWarning',{configurable:true,writable:true,value:function(message,type,code,ctor){'use strict';trace.push({same:ctor===parent.set,receiver:this,code})}});
        \\a.parent=b;if(a.parent!==b||trace.length!==2||!trace[1].same||trace[1].receiver!==undefined||trace[1].code!=='DEP0144')throw Error('setter separate warning/shared code');
        \\}finally{Object.defineProperty(process,'emitWarning',descriptor)}export const passed=true;
    , "node-module-pending-deprecation.mjs");
    defer engine.freeValue(result);
}

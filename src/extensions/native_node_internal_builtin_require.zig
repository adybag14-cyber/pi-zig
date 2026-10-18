// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Private Node realm requireBuiltin over real native builtin admissions.
//! No public Module/load hooks/file context, JS compilation, invented Module
//! record or replacement exports object is involved. Admissions name actual
//! installed native module records, not a claimed complete Node builtinIds map.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = @import("native_node_internal_builtin_scope.zig").Scope;
const functions = @import("native_node_module_callable.zig");
const key = "pi-native:private/internal-builtin-require";
pub const Binding = struct {
    /// Actual realm builtin id, e.g. util (never node:util).
    id: []const u8,
    /// Canonical Engine.registerDefaultModule record, e.g. node:util.
    module_name: []const u8,
};
pub const Inputs = struct {
    /// Explicit trusted converted-native admissions. On actual invocation each default export is
    /// obtained from the existing actual Engine registry; callers supply no
    /// exports, completion flags, handler callbacks or synthetic namespaces.
    bindings: []const Binding,
};
/// Genuine readiness check after native providers publish their completed
/// default exports. Does not mark a missing or partial backend as loaded.
pub fn validateInstalled(engine:*v.em.Engine,inputs:Inputs)!void {
    var s=Scope.init(engine);
    const result=validateBody(&s,inputs);
    const value=try s.finish(if(result)|_|c.pi_js_undefined()else |err|err);engine.freeValue(value);
}
fn validateBody(s:*Scope,inputs:Inputs)!void {
    try s.pending();if(inputs.bindings.len==0 or inputs.bindings.len>512)return error.ActualInternalBuiltinBindingsRequired;
    for(inputs.bindings)|binding|_=try actualExports(s,binding);
}
/// Owned genuine ordinary requireBuiltin. Repeated subset acquisition returns
/// the SAME per-Engine callable only after checking each provider admission.
/// All admissions must be selected before bootstrap exposure; this function
/// does not extend an existing owner or claim a complete internal registry.
/// Acquisition precedes native initialization; it never declares missing exports
/// ready. Invocation fails closed until that real native backend is installed.
pub fn acquire(engine:*v.em.Engine,inputs:Inputs)!c.JSValue {
    var s=Scope.init(engine);var outputs=[_]c.JSValue{c.pi_js_undefined()};var host_error:?anyerror=null;
    var attempt:?c.JSValue=null;
    if(acquireBody(&s,inputs,&attempt))|function|outputs[0]=function else |err|host_error=err;
    s.boundary.retire(host_error,&s.values,&outputs);
    if(s.boundary.failed(host_error))if(attempt)|record| {
        if(engine.native_module_values.get(key))|current|if(c.JS_IsStrictEqual(engine.context,current,record)) {
            var owned=engine.native_module_values.fetchRemove(key).?.value;s.boundary.release(&owned);
        };
    };
    try s.boundary.finishRetired(host_error,&outputs);return outputs[0];
}
fn valid(binding:Binding)bool {
    return binding.id.len!=0 and binding.id.len<=512 and binding.module_name.len!=0 and binding.module_name.len<=1024 and
        std.mem.indexOfScalar(u8,binding.id,0)==null and std.mem.indexOfScalar(u8,binding.module_name,0)==null and
        !std.mem.startsWith(u8,binding.id,"node:") and !std.mem.startsWith(u8,binding.id,"pi-native:") and
        !std.mem.startsWith(u8,binding.module_name,"pi-native:");
}
fn actualExports(s:*Scope,binding:Binding)!c.JSValue {
    if(!valid(binding))return error.InvalidActualInternalBuiltinBinding;
    const known=s.engine.native_module_values.get(binding.module_name) orelse return error.ActualInternalBuiltinNotInstalled;
    const record=try s.own(c.JS_DupValue(s.engine.context,known));
    const atom=try v.js.atom(s.engine,try s.text("default"));defer c.JS_FreeAtom(s.engine.context,atom);
    var descriptor:c.JSPropertyDescriptor=undefined;
    const status=c.JS_GetOwnProperty(s.engine.context,&descriptor,record,atom);
    if(status<0){try s.pending();return error.MissingActualInternalBuiltinPropertyReason;}
    if(status==0){try s.pending();return error.ActualInternalBuiltinDefaultRequired;}
    var owned=[_]c.JSValue{descriptor.value,descriptor.getter,descriptor.setter};
    defer for(&owned)|*value|s.boundary.release(value);
    try s.pending();
    // registerDefaultModule publishes an OWN DATA binding. An inherited or
    // getter-synthesized default cannot declare a native backend completed.
    if(descriptor.flags&c.JS_PROP_GETSET!=0 or c.JS_IsUndefined(owned[0]))return error.ActualInternalBuiltinDefaultRequired;
    return s.own(c.JS_DupValue(s.engine.context,owned[0]));
}
fn mapCall(s:*Scope,method:c.JSValue,map:c.JSValue,args:[]const c.JSValue)!c.JSValue { return s.call(method,map,args); }
fn acquireBody(s:*Scope,inputs:Inputs,attempt:*?c.JSValue)!c.JSValue {
    try s.pending();if(inputs.bindings.len==0 or inputs.bindings.len>512)return error.ActualInternalBuiltinBindingsRequired;
    for(inputs.bindings,0..)|binding,index| {
        if(!valid(binding))return error.InvalidActualInternalBuiltinBinding;
        for(inputs.bindings[0..index])|prior|if(std.mem.eql(u8,prior.id,binding.id))return error.DuplicateActualInternalBuiltinBinding;
    }
    if(s.engine.native_module_values.get(key))|known| {
        const record=try s.own(c.JS_DupValue(s.engine.context,known));
        if(!s.truthy(try s.get(record,"ready")))return error.InternalBuiltinOwnerReentry;
        const map=try s.get(record,"bindings");const get=try s.get(record,"get");const has=try s.get(record,"has");
        for(inputs.bindings)|binding| {
            const id=try s.text(binding.id);
            if(!s.truthy(try mapCall(s,has,map,&.{id})))return error.InternalBuiltinOwnerAdmissionConflict;
            if(!c.JS_IsStrictEqual(s.engine.context,try mapCall(s,get,map,&.{id}),try s.text(binding.module_name)))return error.InternalBuiltinOwnerAuthorityConflict;
        }
        return c.JS_DupValue(s.engine.context,try s.get(record,"require"));
    }
    const record=try s.checked(c.JS_NewObjectProto(s.engine.context,c.pi_js_null()));try s.put(record,"ready",c.pi_js_bool(s.engine.context,0));
    const retained=c.JS_DupValue(s.engine.context,record);
    s.engine.native_module_values.put(s.engine.gpa,key,retained) catch |err|{var value=retained;s.boundary.release(&value);return err;};
    attempt.*=retained;var committed=false;
    defer if(!committed) {
        attempt.*=null;
        if(s.engine.native_module_values.get(key))|known|if(c.JS_IsStrictEqual(s.engine.context,known,record)) {
            var value=s.engine.native_module_values.fetchRemove(key).?.value;s.boundary.release(&value);
        };
    };
    // Capture real primordial methods before guest exposure. These roots are
    // retained/marked/charged by the existing native callable implementation.
    const global=try s.checked(c.JS_GetGlobalObject(s.engine.context));const map_class=try s.get(global,"Map");
    const prototype=try s.get(map_class,"prototype");const get=try s.get(prototype,"get");const has=try s.get(prototype,"has");const set=try s.get(prototype,"set");
    const map=try s.construct(map_class,&.{});const loaded=try s.construct(map_class,&.{});
    for(inputs.bindings)|binding|{_=try mapCall(s,set,map,&.{try s.text(binding.id),try s.text(binding.module_name)});}
    const function=try s.own(try functions.create(s.engine,"requireBuiltin",1,true,invoke,&.{map,get,has,loaded,set}));
    try s.put(record,"bindings",map);try s.put(record,"get",get);try s.put(record,"has",has);try s.put(record,"require",function);try s.put(record,"ready",c.pi_js_bool(s.engine.context,1));
    committed=true;return c.JS_DupValue(s.engine.context,function);
}
fn invoke(engine:*v.em.Engine,_:c.JSValue,args:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue {
    var s=Scope.init(engine);return s.finish(invokeBody(&s,if(args.len==0)c.pi_js_undefined()else args[0],roots));
}
fn invokeBody(s:*Scope,id:c.JSValue,roots:[]const c.JSValue)!c.JSValue {
    try s.pending();
    if(!s.truthy(try mapCall(s,roots[2],roots[0],&.{id})))return error.UnadmittedActualInternalBuiltin;
    if(s.truthy(try mapCall(s,roots[2],roots[3],&.{id})))return c.JS_DupValue(s.engine.context,try mapCall(s,roots[1],roots[3],&.{id}));
    const key_name=try mapCall(s,roots[1],roots[0],&.{id});
    const name=try s.engine.toString(key_name);defer s.engine.gpa.free(name);
    const exports=try actualExports(s,.{.id="admitted",.module_name=name});
    // The actual native backend has now completed and published its default.
    // Retain that exact object for the loaded fast path; failed lookup above
    // commits nothing. Source's JS compiler/moduleLoadList path is not invoked.
    _=try mapCall(s,roots[4],roots[3],&.{id,exports});
    return c.JS_DupValue(s.engine.context,exports);
}

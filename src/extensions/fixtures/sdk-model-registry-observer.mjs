// Actual ModelRegistry class controls. Every subject is the complete retained
// Source class or the genuine installed native SDK class in a fresh Engine.
function registryAssert(value, message) { if (!value) throw new Error(message); }
function registrySame(actual, expected, message) { registryAssert(Object.is(actual, expected), message); }
function registryList(actual, expected, message) {
    registryAssert(actual.length === expected.length && actual.every((value, index) => Object.is(value, expected[index])), message);
}
function registryRestore(object, key, descriptor) {
    if (descriptor) Object.defineProperty(object, key, descriptor); else delete object[key];
}
const registryMethods = [
    ["refresh",1],["getError",0],["getAll",0],["getAvailable",0],["find",2],["findOfType",3],
    ["hasConfiguredAuth",1],["getApiKeyAndHeaders",1],["getProviderAuthStatus",1],["getProvider",1],
    ["stream",3],["streamSimple",3],["complete",3],["getModelsOfType",2],["getAvailableOfType",3],
    ["getModelOfType",3],["classify",3],["generateImages",3],["getProviderDisplayName",1],
    ["getProviderAuth",1],["getApiKeyForProvider",1],["isUsingOAuth",1],["registerProvider",2],
    ["unregisterProvider",1],["registerVirtualModel",1],["unregisterVirtualModel",2],
    ["getRegisteredProviderConfig",1],["getRegisteredNativeProvider",1],["getRegisteredProviderIds",0],
];
function observeRegistryShapes(R) {
    registrySame(R.name,"ModelRegistry","class name");
    registrySame(R.length,1,"class length");
    const prototype = Object.getOwnPropertyDescriptor(R,"prototype");
    registryAssert(prototype && !prototype.writable && !prototype.enumerable && !prototype.configurable,"class prototype descriptor");
    registrySame(prototype.value.constructor,R,"constructor identity");
    registryList(Reflect.ownKeys(R.prototype),["constructor",...registryMethods.map(row=>row[0])],"prototype declaration order");
    const asyncPrototype=Object.getPrototypeOf(async function(){});
    for (const [name,length] of registryMethods) {
        const descriptor=Object.getOwnPropertyDescriptor(R.prototype,name), fn=descriptor.value;
        registryAssert(descriptor.writable && descriptor.configurable && !descriptor.enumerable,"method descriptor");
        registrySame(fn.name,name,"method name"); registrySame(fn.length,length,"method length");
        registryAssert(!Object.hasOwn(fn,"prototype"),"method has no prototype");
        registrySame(Object.getPrototypeOf(fn)===asyncPrototype,name==="getApiKeyAndHeaders"||name==="getApiKeyForProvider","real async prototype");
        registrySame(registryIsAsync(fn),name==="getApiKeyAndHeaders"||name==="getApiKeyForProvider","actual VM async brand");
        let threw=false; try { Reflect.construct(fn,[]); } catch(error) { threw=error instanceof TypeError; }
        registryAssert(threw,"method is nonconstructible");
    }
    let called=false; try { Reflect.apply(R,undefined,[]); } catch(error) { called=error instanceof TypeError; }
    registryAssert(called,"class cannot be called");
}
function observeRegistryConstructor(R) {
    const runtime={}, before=Object.getOwnPropertyDescriptor(R.prototype,"runtime");
    let setterVisits=0;
    try {
        Object.defineProperty(R.prototype,"runtime",{configurable:true,set(){setterVisits++}});
        const registry=new R(runtime), own=Object.getOwnPropertyDescriptor(registry,"runtime");
        registrySame(setterVisits,0,"own class field bypasses inherited setter");
        registryAssert(own.writable && own.enumerable && own.configurable,"own runtime field descriptor");
        registrySame(own.value,runtime,"exact constructor runtime");
        registryList(Reflect.ownKeys(registry),["runtime"],"no hidden public fields");
        registry.runtime=17; registrySame(registry.runtime,17,"runtime remains ordinary mutable public field");
        class Derived extends R {}
        const derived=new Derived(runtime);
        registrySame(Object.getPrototypeOf(derived),Derived.prototype,"subclass prototype");
        registrySame(derived.runtime,runtime,"subclass initialization");
    } finally { registryRestore(R.prototype,"runtime",before); }
    const trace=[], custom={};
    const target=new Proxy(function Target(){},{get(object,key,receiver){if(key==="prototype"){trace.push(key);return custom}return Reflect.get(object,key,receiver)}});
    const viaTarget=Reflect.construct(R,[runtime],target);
    registrySame(Object.getPrototypeOf(viaTarget),custom,"actual newTarget prototype");
    registryList(trace,["prototype"],"single newTarget prototype read");
    const reason={};
    const failed=new Proxy(function(){},{get(object,key,receiver){if(key==="prototype")throw reason;return Reflect.get(object,key,receiver)}});
    let caught;try{Reflect.construct(R,[runtime],failed)}catch(error){caught=error}
    registrySame(caught,reason,"newTarget getter abrupt identity");
}
function observeRegistryRuntimeRetirement(R,hooks) {
    const registry=new R({holder:hooks.make(0)});
    registrySame(hooks.count(0),0,"public runtime is live");
    registry.runtime=undefined;
    registrySame(hooks.count(0),1,"replacing unbranded runtime retires sole original");
    let reads=0;
    Object.defineProperty(registry,"runtime",{configurable:true,get(){reads++;return {getError(){return reads}}}});
    registrySame(registry.getError(),1,"first live runtime");
    registrySame(registry.getError(),2,"second live runtime");
}
function observeRegistryDelegation(R) {
    const rows=[
        ["refresh","refresh",1],["getError","getError",0],["find","getModel",2],["findOfType","getModelOfType",3],
        ["getProviderAuthStatus","getProviderAuthStatus",1],["getProvider","getProvider",1],
        ["stream","stream",3],["streamSimple","streamSimple",3],["complete","complete",3],
        ["getModelsOfType","getModelsOfType",2],["getAvailableOfType","getAvailableOfType",3],
        ["getModelOfType","getModelOfType",3],["classify","classify",3],["generateImages","generateImages",3],
        ["getProviderAuth","getAuth",1],["getRegisteredProviderConfig","getRegisteredProviderConfig",1],
        ["getRegisteredNativeProvider","getRegisteredNativeProvider",1],["getRegisteredProviderIds","getRegisteredProviderIds",0],
    ];
    const given=[{n:0},{n:1},{n:2},{n:3}];
    for(const [name,mapped,count] of rows) for(const supplied of [[],given]) {
        const trace=[],sentinel={name};let actualRuntime;
        const registry=new R(undefined);
        Object.defineProperty(registry,"runtime",{get(){trace.push("runtime");return actualRuntime={
            get [mapped](){trace.push("callee");return function(...args){
                trace.push("call");registrySame(this,actualRuntime,"runtime call receiver");
                registrySame(args.length,count,"source explicit argument count");
                for(let i=0;i<count;i++)registrySame(args[i],supplied[i],"source argument position");
                return sentinel;
            }}
        }}});
        registrySame(Reflect.apply(R.prototype[name],registry,supplied),sentinel,"ordinary exact result identity");
        registryList(trace,["runtime","callee","call"],"delegation evaluation order");
    }
}
function observeRegistryProviderArguments(R) {
    for(const name of ["hasConfiguredAuth","isUsingOAuth"]) {
        const trace=[],provider=Symbol("provider");let runtime;
        const registry=new R(undefined);
        Object.defineProperty(registry,"runtime",{get(){trace.push("runtime");return runtime={
            get [name](){trace.push("callee");return function(value){trace.push("call");registrySame(this,runtime,"provider receiver");registrySame(value,provider,"provider argument");return 31}}
        }}});
        const model={get provider(){trace.push("provider");return provider}};
        registrySame(registry[name](model),31,"no extra Boolean coercion");
        registryList(trace,["runtime","callee","provider","call"],"callee before argument getter");
    }
}
function observeRegistryDisplayName(R) {
    const descriptor=Object.getOwnPropertyDescriptor(Number.prototype,"name"), sentinel={}, provider={};
    try {
        Object.defineProperty(Number.prototype,"name",{configurable:true,get(){registrySame(this,0,"primitive optional receiver");return sentinel}});
        registrySame(new R({getProvider(){return 0}}).getProviderDisplayName(provider),sentinel,"primitive optional name");
    } finally {registryRestore(Number.prototype,"name",descriptor)}
    for(const value of [undefined,null]) registrySame(new R({getProvider(){return value}}).getProviderDisplayName(provider),provider,"nullish provider fallback");
    for(const value of [undefined,null,false,0,""]) {
        const result=new R({getProvider(){return {name:value}}}).getProviderDisplayName(provider);
        registrySame(result,value==null?provider:value,"nullish name only");
    }
}
function observeRegistrySnapshots(R) {
    const ArrayOriginal=Array, fromDescriptor=Object.getOwnPropertyDescriptor(ArrayOriginal,"from");
    try {
        Object.defineProperty(ArrayOriginal,"from",{configurable:true,get(){throw new Error("Array.from must not be read")}});
        globalThis.Array=function(){throw new Error("global Array must not construct a literal")};
        for(const [name,method] of [["getAll","getModels"],["getAvailable","getAvailableSnapshot"]]) {
            const first={},second={};let calls=0,steps=0;
            const iterable={[Symbol.iterator](){calls++;return {next(){steps++;return steps===1?{value:first,done:false}:steps===2?{value:second,done:false}:{done:true}}}}};
            const rows=new R({[method](){return iterable}})[name]();
            registryAssert(ArrayOriginal.isArray(rows),"actual array literal result");
            registryList(rows,[first,second],"spread values");registrySame(calls,1,"one actual iterator factory call");
            registrySame(steps,3,"iterator done step");
        }
    } finally {globalThis.Array=ArrayOriginal;registryRestore(ArrayOriginal,"from",fromDescriptor)}
}
function observeRegistrySnapshotRetirement(R,hooks) {
    const iterable={holder:hooks.make(2),get [Symbol.iterator](){
        registrySame(hooks.count(0),1,"temporary runtime retires before spread");
        registrySame(hooks.count(1),1,"temporary callee retires before spread");
        return function(){return {next(){return {done:true}}}}
    }};
    let only=iterable;
    const registry=new R(undefined);
    Object.defineProperty(registry,"runtime",{get(){return {holder:hooks.make(0),get getModels(){
        const fn=function(){const value=only;only=undefined;return value};fn.holder=hooks.make(1);return fn;
    }}}});
    // Drop the fixture's own iterable owner before the public call.
    return function(){
        const result=registry.getAll();
        registrySame(result.length,0,"spread completed");
        registrySame(hooks.count(2),1,"iterable temporary retires by method return");
    };
}
function observeRegistryVoids(R,hooks) {
    const seen=[];
    const runtime={
        registerProvider(...args){seen.push(["name",...args]);return hooks.make(0)},
        registerNativeProvider(...args){seen.push(["native",...args]);return hooks.make(1)},
        unregisterProvider(...args){seen.push(["remove",...args]);return hooks.make(2)},
        registerVirtualModel(...args){seen.push(["virtual",...args]);return hooks.make(3)},
        unregisterVirtualModel(...args){seen.push(["removeVirtual",...args]);return hooks.make(4)},
    };
    const registry=new R(runtime), config={}, provider={}, definition={};
    registrySame(registry.registerProvider("x",config),undefined,"register by name void");
    registrySame(registry.registerProvider(provider),undefined,"register provider void");
    registrySame(registry.unregisterProvider("x"),undefined,"unregister void");
    registrySame(registry.registerVirtualModel(definition),undefined,"virtual void");
    registrySame(registry.unregisterVirtualModel("x","y"),undefined,"remove virtual void");
    registryList(seen.map(row=>row[0]),["name","native","remove","virtual","removeVirtual"],"selected methods");
    registryList(seen[0],["name","x",config],"config arguments");registryList(seen[1],["native",provider],"native argument");
    registryList(seen[3],["virtual",definition],"definition argument");registryList(seen[4],["removeVirtual","x","y"],"remove arguments");
    for(let i=0;i<5;i++)registrySame(hooks.count(i),1,"discarded statement result retired");
}
function observeRegistryRegistrationError(R) {
    const ErrorOriginal=Error, descriptor=Object.getOwnPropertyDescriptor(globalThis,"Error"),reason={},trace=[];
    const registry=new R(undefined);
    Object.defineProperty(registry,"runtime",{get(){trace.push("runtime");throw ErrorOriginal("late runtime")}});
    try {
        Object.defineProperty(globalThis,"Error",{configurable:true,get(){trace.push("Error");return function(message){
            trace.push("construct");registryAssert(new.target!==undefined,"actual Error constructor");
            registrySame(message,"Provider config is required when registering by name","exact registration message");return reason;
        }}});
        let caught;try{registry.registerProvider("x",0)}catch(error){caught=error}
        registrySame(caught,reason,"live Error result is explicitly thrown");
        registryList(trace,["Error","construct"],"error before runtime lookup");
    }finally{registryRestore(globalThis,"Error",descriptor)}
}
async function observeRegistryAwait(R) {
    const PromiseOriginal=Promise, descriptor=Object.getOwnPropertyDescriptor(globalThis,"Promise");
    let sync=true,calls=0,reads=0;
    const runtime={getAuth(){calls++;return {get auth(){reads++;registryAssert(!sync,"body resumes after genuine Await");return {apiKey:"secret"}},env:undefined}}};
    try {
        Object.defineProperty(globalThis,"Promise",{configurable:true,writable:true,value:function(){throw new Error("global Promise is not the AF constructor")}});
        const registry=new R(runtime), headers=registry.getApiKeyAndHeaders({provider:"p"}), key=registry.getApiKeyForProvider("p");
        registrySame(calls,2,"both bodies begin synchronously");registrySame(reads,0,"neither body continues before Await");
        registrySame(Object.getPrototypeOf(headers),PromiseOriginal.prototype,"intrinsic headers Promise");
        registrySame(Object.getPrototypeOf(key),PromiseOriginal.prototype,"intrinsic key Promise");
        sync=false;
        const actualHeaders=await headers;registrySame(actualHeaders.apiKey,"secret","headers awaited result");
        registrySame(await key,"secret","key awaited result");registryAssert(reads>=4,"live auth accesses");
    }finally{registryRestore(globalThis,"Promise",descriptor)}
}
async function observeRegistryResolved(R,hooks) {
    const trace=[],headers={},env={},resolution={get auth(){
        const index=trace.filter(item=>item.startsWith("auth")).length;
        if(index>0)registrySame(hooks.count(index-1),1,"previous auth receiver retired");
        if(index===3)registrySame(hooks.count(4),1,"baseUrl predicate retired before repeated auth read");
        trace.push("auth"+index);
        return {holder:hooks.make(index),
            get apiKey(){trace.push("key");return 7},
            get headers(){trace.push("headers");return headers},
            get baseUrl(){trace.push("base");return index===2?hooks.make(4):"https://actual.invalid"}
        };
    },get env(){trace.push("env");return env}};
    const result=await new R({getAuth(){return resolution}}).getApiKeyAndHeaders({provider:"p"});
    registryList(trace,["auth0","key","auth1","headers","auth2","base","auth3","base","env"],"repeated resolution fields");
    registryList(Object.keys(result),["ok","apiKey","headers","baseUrl","env"],"resolved property order");
    registrySame(result.apiKey,7,"raw api key");registrySame(result.headers,headers,"headers identity");
    registrySame(result.baseUrl,"https://actual.invalid","selected baseUrl");registrySame(result.env,env,"env identity");
    registrySame(hooks.count(3),1,"last auth receiver retired");
    const absent=await new R({getAuth(){return {auth:{apiKey:"a",headers,baseUrl:0},env}}}).getApiKeyAndHeaders({});
    registryAssert(!Object.hasOwn(absent,"baseUrl"),"false baseUrl omits own property");
}
async function observeRegistryCompatibility(R,hooks) {
    const trace=[],headers={},registry=new R(undefined);let reads=0;
    Object.defineProperty(registry,"runtime",{get(){reads++;return reads===1?{getAuth(){trace.push("getAuth");return null}}:{
        get getCompatibilityRequestConfig(){trace.push("method");return function(model){trace.push("compatibility");registrySame(model.provider,"p","compatibility argument");return {get authHeader(){trace.push("authHeader");return false},get headers(){trace.push("headers");return headers}}}}
    }}});
    const result=await registry.getApiKeyAndHeaders({provider:"p"});
    registryList(trace,["getAuth","method","compatibility","authHeader","headers"],"compatibility after live second runtime");
    registrySame(result.headers,headers,"compatibility headers");registryList(Object.keys(result),["ok","headers"],"compatibility shape");
    const model={get provider(){registrySame(hooks.count(0),1,"authHeader predicate retires before provider");return {[Symbol.toPrimitive](hint){registrySame(hint,"string","template string hint");return "provider"}}}};
    const missing=await new R({getAuth(){return undefined},getCompatibilityRequestConfig(){return {get authHeader(){return hooks.make(0)}}}}).getApiKeyAndHeaders(model);
    registrySame(missing.ok,false,"missing key result");registrySame(missing.error,'No API key found for "provider"',"missing key message");
}
async function observeRegistryCatchSelection(R) {
    const descriptor=Object.getOwnPropertyDescriptor(globalThis,"Error"),trace=[],message={},cause={get message(){trace.push("cause.message");return "unused"}};
    const reason={get cause(){trace.push("cause");return cause},get message(){trace.push("error.message");return message}};
    try {
        Object.defineProperty(globalThis,"Error",{configurable:true,get(){trace.push("Error");return {[Symbol.hasInstance](value){
            trace.push(value===reason?"is:error":value===cause?"is:cause":"is:other");return value===reason;
        }}}});
        const result=await new R({getAuth(){throw reason}}).getApiKeyAndHeaders({});
        registrySame(result.error,message,"raw caught message identity");
        registryList(trace,["Error","is:error","cause","Error","is:cause","Error","is:error","error.message"],"live repeated instanceof checks");
    }finally{registryRestore(globalThis,"Error",descriptor)}
    const inner=new Error("inner"),outer=new Error("outer");outer.cause=inner;
    registrySame((await new R({getAuth(){return Promise.reject(outer)}}).getApiKeyAndHeaders({})).error,"inner","real Error cause message");
}
async function observeRegistryCatchStringAndAbrupt(R) {
    const descriptor=Object.getOwnPropertyDescriptor(globalThis,"String"),reason={},rendered={};let calls=0;
    try{
        Object.defineProperty(globalThis,"String",{configurable:true,writable:true,value:function(value){calls++;registrySame(value,reason,"actual global String argument");return rendered}});
        registrySame((await new R({getAuth(){throw reason}}).getApiKeyAndHeaders({})).error,rendered,"live String raw result");
        registrySame(calls,1,"String called once");
    }finally{registryRestore(globalThis,"String",descriptor)}
    const abrupt={},error=new Error("x");Object.defineProperty(error,"cause",{get(){throw abrupt}});
    let caught;try{await new R({getAuth(){throw error}}).getApiKeyAndHeaders({})}catch(value){caught=value}
    registrySame(caught,abrupt,"failure inside catch escapes actual AF");
}
async function observeRegistryMissingTemplate(R) {
    const concat=Object.getOwnPropertyDescriptor(String.prototype,"concat"),StringOriginal=String,stringDescriptor=Object.getOwnPropertyDescriptor(globalThis,"String"),hints=[];
    try {
        Object.defineProperty(StringOriginal.prototype,"concat",{configurable:true,get(){throw new Error("intrinsic template cannot use concat")}});
        Object.defineProperty(globalThis,"String",{configurable:true,writable:true,value:function(){throw new Error("template cannot call global String")}});
        const model={provider:{[Symbol.toPrimitive](hint){hints.push(hint);return "raw"}}};
        const result=await new R({getAuth(){return undefined},getCompatibilityRequestConfig(){return {authHeader:true}}}).getApiKeyAndHeaders(model);
        registrySame(result.error,'No API key found for "raw"',"intrinsic eager missing template");registryList(hints,["string"],"one string-hint conversion");
    }finally{registryRestore(globalThis,"String",stringDescriptor);registryRestore(StringOriginal.prototype,"concat",concat)}
    const error=new Error("authHeader requires a resolved API key");
    registrySame((await new R({getAuth(){throw error}}).getApiKeyAndHeaders({provider:"rewritten"})).error,'No API key found for "rewritten"',"exact cause message substitution");
}
async function observeRegistryKey(R) {
    const poison=new Proxy({},{get(){throw new Error("caught reason must not be inspected")}});
    for(const supplied of [undefined,null]) registrySame(await new R({getAuth(){return supplied}}).getApiKeyForProvider("p"),undefined,"nullish optional key");
    registrySame(await new R({getAuth(){throw poison}}).getApiKeyForProvider("p"),undefined,"synchronous ordinary empty catch");
    registrySame(await new R({getAuth(){return Promise.reject(poison)}}).getApiKeyForProvider("p"),undefined,"rejected ordinary empty catch");
    registrySame(await new R({getAuth(){return {get auth(){throw poison}}}}).getApiKeyForProvider("p"),undefined,"post-Await getter empty catch");
    const sentinel={};registrySame(await new R({getAuth(){return {auth:{apiKey:sentinel}}}}).getApiKeyForProvider("p"),sentinel,"actual key result");
}
async function observeRegistryData(R,hooks,route) {
    let data;
    const runtime={getAuth(){
        if(route==="headers:start"||route==="key:start"){data=hooks.freshPrivateData();throw data}
        return {get auth(){data=hooks.freshPrivateData();throw data}};
    }};
    const registry=new R(runtime);
    const result=route.startsWith("headers")?await registry.getApiKeyAndHeaders({provider:"p"}):await registry.getApiKeyForProvider("p");
    registryAssert(hooks.isUnmarkedPrivateData(data),"successful private DATA stays ordinary");
    if(route.startsWith("headers"))registrySame(result.error,data.message,"ordinary native Error message selected");
    else registrySame(result,undefined,"ordinary DATA reaches the source empty catch");
}
function prepareRegistryAwaitLifetime(R,hooks) {
    let release;
    const gate=new Promise(resolve=>{release=resolve});
    let receiver={holder:hooks.make(0),runtime:{getAuth(){return gate}}},model={holder:hooks.make(1)};
    const pending=R.prototype.getApiKeyAndHeaders.call(receiver,model);
    receiver=undefined;model=undefined;
    return {pending,release};
}
async function observeRegistryAwaitLifetime(R,hooks) {
    const state=prepareRegistryAwaitLifetime(R,hooks);
    registrySame(hooks.count(0),0,"receiver retained during real Await");registrySame(hooks.count(1),0,"argument retained during real Await");
    const original=Object.getOwnPropertyDescriptor(Object.prototype,"then"),marker={};let adoption=0;
    try {
        Object.defineProperty(Object.prototype,"then",{configurable:true,get(){
            if(Object.hasOwn(this,"ok") && this.env===marker){
                adoption++;registrySame(hooks.count(0),0,"receiver live in return adoption");
                registrySame(hooks.count(1),0,"argument live in return adoption");
                registrySame(hooks.count(2),0,"resolution local live in return adoption");
            }
            return undefined;
        }});
        state.release({holder:hooks.make(2),auth:{apiKey:"a"},env:marker});
        state.release=undefined;
        const result=await state.pending;registrySame(result.env,marker,"actual adopted record");
        registrySame(adoption,1,"one AF returned-record adoption");
    }finally{registryRestore(Object.prototype,"then",original)}
    registrySame(hooks.count(0),1,"receiver retired after settlement");registrySame(hooks.count(1),1,"argument retired after settlement");
    registrySame(hooks.count(2),1,"resolution local retired after settlement");
}
async function observeRegistryCatchLifetime(R,hooks) {
    const OriginalError=Error,descriptor=Object.getOwnPropertyDescriptor(globalThis,"Error"),thenDescriptor=Object.getOwnPropertyDescriptor(Object.prototype,"then");
    let adopted=0;
    try {
        Object.defineProperty(globalThis,"Error",{configurable:true,writable:true,value:{[Symbol.hasInstance](value){return value!==undefined}}});
        Object.defineProperty(Object.prototype,"then",{configurable:true,get(){
            if(Object.hasOwn(this,"ok") && this.ok===false && this.error==="kept"){
                adopted++;registrySame(hooks.count(0),0,"catch error local retained through adoption");registrySame(hooks.count(1),0,"catch cause local retained through adoption");
            }return undefined;
        }});
        const registry=new R({getAuth(){throw {holder:hooks.make(0),cause:{holder:hooks.make(1),message:"kept"}}}});
        registrySame((await registry.getApiKeyAndHeaders({})).error,"kept","catch record returned");
    }finally{registryRestore(Object.prototype,"then",thenDescriptor);registryRestore(globalThis,"Error",descriptor)}
    registrySame(adopted,1,"actual catch record adoption");registrySame(hooks.count(0),1,"catch error retired");registrySame(hooks.count(1),1,"catch cause retired");
    registryAssert(OriginalError!==undefined,"original realm retained");
}
async function observeRegistryKeyAdoption(R,hooks) {
    const result={get then(){registrySame(hooks.count(0),0,"actual reaction job still owns fulfilled input during key adoption");return undefined}};
    const registry=new R({getAuth(){return {holder:hooks.make(0),auth:{apiKey:result}}}});
    registrySame(await registry.getApiKeyForProvider("p"),result,"key adopted once");
    registrySame(hooks.count(0),1,"reaction input retires after its completed job");
}
async function observeRegistryCurrentFatal(R,hooks,key=false) {
    hooks.freshPrivateData();
    const descriptor=Object.getOwnPropertyDescriptor(globalThis,"Error");
    Object.defineProperty(globalThis,"Error",{configurable:true,get(){hooks.visit(1);return descriptor.value}});
    const receiver={get runtime(){
        hooks.raiseNativeFatal();
        return {getAuth(){hooks.visit(2)}};
    }};
    const pending=key?R.prototype.getApiKeyForProvider.call(receiver,"p"):
        R.prototype.getApiKeyAndHeaders.call(receiver,{get provider(){hooks.visit(2);return "late"}});
    await pending.catch(()=>{hooks.visit(3);hooks.record.guestReached=true});
}
async function observeRegistryPredicateStop(R,hooks,cancel) {
    const ErrorOriginal=Error;
    Object.defineProperty(globalThis,"Error",{configurable:true,get(){hooks.visit(2);return ErrorOriginal}});
    const model={get provider(){hooks.visit(1);return "late"}};
    const registry=new R({getAuth(){return null},getCompatibilityRequestConfig(){return {get authHeader(){
        if(cancel)hooks.armCancel(0);else hooks.armFatal(0);return hooks.make(0);
    }}}});
    await registry.getApiKeyAndHeaders(model).catch(()=>hooks.visit(3));
}

function observeRegistryForeignTarget(R, foreign) {
    const runtime={}, value=Reflect.construct(R,[runtime],foreign.target);
    registrySame(Object.getPrototypeOf(value),foreign.objectPrototype,"primitive newTarget prototype uses its own actual realm");
    registrySame(value.runtime,runtime,"foreign newTarget keeps actual runtime field");
}

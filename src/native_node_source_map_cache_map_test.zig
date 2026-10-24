//! Actual-VM controls for SourceMapCacheMap weak ownership and observable order.
//! Test collaborators observe the native owner; production never evaluates JS.
const std = @import("std");
const em = @import("extensions/engine.zig");
const cache_owner = @import("extensions/native_node_source_map_cache_map.zig");
const c = em.c;
const Probe = struct { engine: *em.Engine, retired: usize = 0, emit_fatal: bool = false, first: c.JSValue };
fn finalizeProbe(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const probe: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    probe.retired += 1;
    if (probe.emit_fatal) {
        _ = probe.engine.throwNativeOutOfMemoryFatal();
        if (c.JS_HasException(probe.engine.context)) {
            const reason = c.JS_GetException(probe.engine.context);
            if (c.JS_IsUndefined(probe.first)) probe.first = c.JS_DupValue(probe.engine.context, reason);
            probe.engine.freeValue(reason); // The actual native invocation still owns it.
        }
    }
}
fn rawTakenFatal(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    _ = engine.throwNativeOutOfMemoryFatal();
    if (c.JS_HasException(engine.context)) engine.freeValue(c.JS_GetException(engine.context));
    return c.pi_js_undefined();
}
const Fixture = struct {
    engine: *em.Engine,
    probe_class: c.JSClassID = 0,
    fn init() !Fixture {
        const engine = try em.Engine.init(std.testing.allocator, .{});
        errdefer engine.deinit();
        var f: Fixture = .{ .engine = engine };
        try f.run(
            \\globalThis.debugCalls=[];globalThis.debugBinds=0;globalThis.debugInitialCalls=0;
            \\globalThis.debuglogFixture=function(name,assign) {
            \\  if(name!=='source_map')throw Error('wrong original debug category');
            \\  debugBinds++;globalThis.assignCacheDebug=assign;
            \\  const enabled=function(message){debugCalls.push(message)};
            \\  return function(message){debugInitialCalls++;assign(enabled);return enabled(message)};
            \\};
        );
        try f.createClass("Cache");
        return f;
    }
    fn deinit(self: *Fixture) void { self.engine.deinit(); }
    fn eval(self: *Fixture, source: []const u8) !c.JSValue {
        return self.engine.eval(source, "source-map-cache-control.js", c.JS_EVAL_TYPE_GLOBAL);
    }
    fn run(self: *Fixture, source: []const u8) !void {
        const result = try self.eval(source); self.engine.freeValue(result);
        try std.testing.expect(!c.JS_HasException(self.engine.context));
    }
    fn global(self: *Fixture, name: [*:0]const u8) !c.JSValue {
        const object = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context)); defer self.engine.freeValue(object);
        return self.engine.checked(c.JS_GetPropertyStr(self.engine.context, object, name));
    }
    fn publish(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        const object = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context)); defer self.engine.freeValue(object);
        if (c.JS_DefinePropertyValueStr(self.engine.context, object, name, c.JS_DupValue(self.engine.context, value), c.JS_PROP_C_W_E) < 0)
            return error.SourceMapControlPublicationFailed;
    }
    fn createClass(self: *Fixture, name: [*:0]const u8) !void {
        const logger = try self.global("debuglogFixture"); defer self.engine.freeValue(logger);
        const constructor_value = try cache_owner.create(self.engine, .{ .debuglog = logger }); defer self.engine.freeValue(constructor_value);
        try self.publish(name, constructor_value);
    }
    fn sentinel(self: *Fixture, probe: *Probe) !c.JSValue {
        if (self.probe_class == 0) {
            if (c.JS_NewClassID(self.engine.runtime, &self.probe_class) == 0) return error.OutOfMemory;
            const definition: c.JSClassDef = .{ .class_name = "Source map actual lifetime probe", .finalizer = finalizeProbe };
            if (c.JS_NewClass(self.engine.runtime, self.probe_class, &definition) < 0) return error.OutOfMemory;
        }
        const result = try self.engine.checked(c.JS_NewObjectClass(self.engine.context, self.probe_class));
        _ = c.JS_SetOpaque(result, probe); return result;
    }
    fn publishProbe(self: *Fixture, name: [*:0]const u8, probe: *Probe) !void {
        const value = try self.sentinel(probe); defer self.engine.freeValue(value); try self.publish(name, value);
    }
    fn checkpoint(self: *Fixture) void { self.engine.finishJob(); c.JS_RunGC(self.engine.runtime); }
    fn drain(self: *Fixture) !usize {
        const count = try self.engine.runReadyJobs(256);
        try std.testing.expect(!c.JS_IsJobPending(self.engine.runtime)); self.engine.finishJob(); return count;
    }
    fn takeReason(self: *Fixture) !c.JSValue {
        if (c.JS_HasException(self.engine.context)) return c.JS_GetException(self.engine.context);
        if (self.engine.captured_exception) |reason| { self.engine.captured_exception = null; return reason; }
        return error.ActualSourceMapFailureRequired;
    }
    fn balanced(self: *Fixture) !void {
        try std.testing.expectEqual(@as(usize, 0), self.engine.native_exception_diagnostics_suppressed);
        try std.testing.expect(self.engine.native_fatal_invocation == null);
    }
};

test "native source map cache class has the original frozen prototype and hidden private instance state" {
    var f = try Fixture.init(); defer f.deinit();
    try f.run(
        \\if(Cache.name!=='SourceMapCacheMap'||Cache.length!==0||typeof Cache!=='function')throw Error('class shape');
        \\if(Object.getPrototypeOf(Cache)!==Function.prototype||Object.getPrototypeOf(Cache.prototype)!==Object.prototype)throw Error('class prototypes');
        \\if(!Object.isFrozen(Cache.prototype)||Object.getOwnPropertyDescriptor(Cache,'prototype').writable)throw Error('class freeze');
        \\if(Object.getOwnPropertyNames(Cache.prototype).join(',')!=='constructor,set,get,size')throw Error('prototype name order');
        \\const sm=new Cache();
        \\if(Reflect.ownKeys(sm).length!==0||sm.size!==0||sm.get('absent')!==undefined)throw Error('private slots visible');
        \\for(const [key,length] of [['set',3],['get',1],[Symbol.iterator,0]]) {
        \\  const d=Object.getOwnPropertyDescriptor(Cache.prototype,key);
        \\  if(d.enumerable||d.configurable||d.writable||d.value.length!==length||Object.hasOwn(d.value,'prototype'))throw Error('method descriptors');
        \\}
        \\const size=Object.getOwnPropertyDescriptor(Cache.prototype,'size');
        \\if(size.enumerable||size.configurable||size.set!==undefined||size.get.name!=='get size'||size.get.length!==0)throw Error('size getter');
        \\for(const call of [()=>Cache(),()=>new Cache.prototype.set(),()=>new Cache.prototype.get()]) {
        \\  let reason;try{call()}catch(e){reason=e}if(!(reason instanceof TypeError))throw Error('constructor admission');
        \\}
        \\if(debugBinds!==1||debugInitialCalls!==0||debugCalls.length!==0)throw Error('debug initialized eagerly');
    );
    try f.balanced();
}
test "native source map cache private brands reject proxies and forged receivers while derived instances work" {
    var f = try Fixture.init(); defer f.deinit();
    try f.run(
        \\class Derived extends Cache{};const actual=new Derived();const data={};
        \\actual.set(['x'],data,{});if(actual.get('x')!==data||!(actual instanceof Derived))throw Error('derived instance');
        \\let prototypeReads=0;const target=new Proxy(function(){},{get(t,k,r){if(k==='prototype'){prototypeReads++;return 7}return Reflect.get(t,k,r)}});
        \\const fallback=Reflect.construct(Cache,[],target);
        \\if(Object.getPrototypeOf(fallback)!==Object.prototype||prototypeReads!==1)throw Error('newTarget fallback');
        \\if(Cache.prototype.get.call(fallback,'missing')!==undefined)throw Error('fresh branded fallback');
        \\let traps=0;const proxy=new Proxy(actual,new Proxy({},{get(){traps++;throw Error('private trap')}}));
        \\for(const receiver of [{},Object.create(actual),proxy,null,3]) {
        \\  for(const call of [()=>Cache.prototype.get.call(receiver,'x'),()=>Object.getOwnPropertyDescriptor(Cache.prototype,'size').get.call(receiver),()=>Cache.prototype[Symbol.iterator].call(receiver)]) {
        \\    let reason;try{call()}catch(e){reason=e}if(!(reason instanceof TypeError))throw Error('forged private brand');
        \\  }
        \\}
        \\if(traps!==0)throw Error('private brand invoked proxy');
    );
}
test "native source map cache aliases share the actual per Engine module data key across classes" {
    var f = try Fixture.init(); defer f.deinit(); try f.createClass("SecondCache");
    try f.run(
        \\const first=new Cache(),second=new SecondCache(),module={},before={},after={};
        \\const key={toString(){throw Error('Map key coerced')}};first.set(['file','source',key,NaN,-0],before,module);
        \\if(first.size!==5||first.get(key)!==before||first.get(NaN)!==before||first.get(+0)!==before)throw Error('Map key semantics');
        \\second.set(['other'],after,module);
        \\if(first.get('file')!==after||first.get('source')!==after||first.get(key)!==after||second.get('other')!==after)throw Error('per-class data key');
        \\if(Reflect.ownKeys(module).length!==0)throw Error('internal private key leaked');
        \\if(first.set([],after,module)!==undefined)throw Error('set returned Map');
    );
}
test "native source map cache forEach keeps holes inherited indices length snapshot and getter order" {
    var f = try Fixture.init(); defer f.deinit();
    try f.run(
        \\const observed=[],base={1:'inherited'},target=Object.create(base);target.length=4;target[0]='first';target[3]='last';
        \\const keys=new Proxy(target,{get(o,k,r){observed.push('get:'+String(k));if(k==='0')o[4]='outside';return Reflect.get(o,k,r)},has(o,k){observed.push('has:'+String(k));return Reflect.has(o,k)}});
        \\const sm=new Cache(),module={},data={};sm.set(keys,data,module);
        \\if(observed.join('|')!=='get:length|has:0|get:0|has:1|get:1|has:2|has:3|get:3')throw Error('forEach order '+observed);
        \\if(sm.size!==3||[...sm].map(x=>x[0]).join(',')!=='first,inherited,last'||sm.get('outside')!==undefined)throw Error('holes or length snapshot');
    );
}
test "native source map cache partial key failure preserves earlier insertions before data and registration" {
    var f = try Fixture.init(); defer f.deinit();
    try f.run(
        \\globalThis.sm=new Cache();globalThis.partialModule={};globalThis.oldData={old:true};globalThis.newData={next:true};
        \\sm.set(['seed'],oldData,partialModule);
        \\const reason={};const keys={length:2,0:'inserted',get 1(){throw reason}};
        \\let caught;try{sm.set(keys,newData,partialModule)}catch(e){caught=e}
        \\if(caught!==reason||sm.size!==2||sm.get('inserted')!==oldData||sm.get('seed')!==oldData)throw Error('partial set ordering');
        \\delete globalThis.partialModule;delete globalThis.oldData;delete globalThis.newData;
    );
    f.checkpoint(); _ = try f.drain();
    try f.run(
        \\if(sm.size!==1||sm.get('inserted')!==undefined||[...sm].length!==0)throw Error('failed set installed finalization keys');
        \\if(debugCalls.length!==1||!debugCalls[0].endsWith('seed'))throw Error('registration ordering');
    );
}
test "native source map cache set checks WeakRef first and delays receiver brand through empty keys" {
    var f = try Fixture.init(); defer f.deinit();
    try f.run(
        \\const sm=new Cache(),module={},first={},replacement={};sm.set(['known'],first,module);
        \\let reads=0;const keys={get length(){reads++;return 0}};
        \\let wrongTarget;try{Cache.prototype.set.call({},keys,replacement,3)}catch(e){wrongTarget=e}
        \\if(!(wrongTarget instanceof TypeError)||reads!==0)throw Error('WeakRef validation order');
        \\let wrongReceiver;try{Cache.prototype.set.call({},keys,replacement,module)}catch(e){wrongReceiver=e}
        \\if(!(wrongReceiver instanceof TypeError)||reads!==1||sm.get('known')!==replacement)throw Error('empty keys brand timing');
        \\let nonempty;try{Cache.prototype.set.call({},['x'],first,module)}catch(e){nonempty=e}
        \\if(!(nonempty instanceof TypeError)||sm.get('known')!==replacement)throw Error('callback brand timing');
    );
}
test "native source map cache private data handles frozen modules and revoked proxy wrappers without traps" {
    var f = try Fixture.init(); defer f.deinit();
    try f.run(
        \\const sm=new Cache(),frozen=Object.freeze({public:1}),one={},two={};sm.set(['frozen'],one,frozen);
        \\if(sm.get('frozen')!==one||!Object.isFrozen(frozen)||Reflect.ownKeys(frozen).join(',')!=='public')throw Error('frozen private Set');
        \\let traps=0;const target={};const pair=Proxy.revocable(target,new Proxy({},{get(){traps++;throw Error('proxy trap')}}));
        \\sm.set(['proxy'],one,pair.proxy);pair.revoke();sm.set(['proxy-again'],two,pair.proxy);
        \\if(sm.get('proxy')!==two||sm.get('proxy-again')!==two||traps!==0||Reflect.ownKeys(target).length!==0)throw Error('wrapper private storage');
        \\sm.set(['frozen-again'],two,frozen);if(sm.get('frozen')!==two)throw Error('private replacement');
    );
}
test "native source map cache owns only WeakRefs so actual module and data retire before cleanup jobs" {
    var f = try Fixture.init(); defer f.deinit();
    var target_probe: Probe = .{ .engine = f.engine, .first = c.pi_js_undefined() };
    var data_probe: Probe = .{ .engine = f.engine, .first = c.pi_js_undefined() };
    try f.publishProbe("weakModule", &target_probe); try f.publishProbe("weakData", &data_probe);
    try f.run(
        \\globalThis.sm=new Cache();globalThis.moduleRef=new WeakRef(weakModule);globalThis.dataRef=new WeakRef(weakData);
        \\sm.set(['file','alias'],weakData,weakModule);delete globalThis.weakModule;delete globalThis.weakData;
    );
    try std.testing.expectEqual(@as(usize, 0), target_probe.retired); try std.testing.expectEqual(@as(usize, 0), data_probe.retired);
    f.checkpoint();
    try std.testing.expectEqual(@as(usize, 1), target_probe.retired); try std.testing.expectEqual(@as(usize, 1), data_probe.retired);
    try std.testing.expect(c.JS_IsJobPending(f.engine.runtime));
    try f.run(
        \\if(moduleRef.deref()!==undefined||dataRef.deref()!==undefined||sm.size!==2||sm.get('file')!==undefined||[...sm].length!==0)throw Error('weak ownership before cleanup');
        \\if(debugCalls.length!==0)throw Error('cleanup callback ran synchronously');
    );
    try std.testing.expect((try f.drain())>0);
    try f.run(
        \\if(sm.size!==0||debugCalls.length!==2||debugInitialCalls!==1)throw Error('real finalization cleanup');
        \\if(!debugCalls[0].endsWith('file')||!debugCalls[1].endsWith('alias'))throw Error('cleanup key order');
    );
    try f.balanced();
}
test "native source map cache successful dereference keeps its target until the actual host checkpoint" {
    var f = try Fixture.init(); defer f.deinit();
    var probe: Probe = .{ .engine = f.engine, .first = c.pi_js_undefined() };
    try f.publishProbe("heldModule", &probe);
    try f.run("globalThis.sm=new Cache();globalThis.heldData={};sm.set(['held'],heldData,heldModule);");
    f.checkpoint();
    try f.run(
        \\if(sm.get('held')!==heldData)throw Error('live get');
        \\delete globalThis.heldModule;delete globalThis.heldData;
    );
    c.JS_RunGC(f.engine.runtime); try std.testing.expectEqual(@as(usize, 0), probe.retired);
    f.checkpoint(); try std.testing.expectEqual(@as(usize, 1), probe.retired);
    _ = try f.drain(); try f.run("if(sm.size!==0)throw Error('checkpoint cleanup');");
}
test "native source map cache stale finalization leaves an alias replaced with a live module intact" {
    var f = try Fixture.init(); defer f.deinit();
    try f.run(
        \\globalThis.sm=new Cache();globalThis.liveModule={};globalThis.liveData={};
        \\{const previous={};sm.set(['shared','obsolete'],{},previous);sm.set(['shared'],liveData,liveModule)}
    );
    f.checkpoint(); _ = try f.drain();
    try f.run(
        \\if(sm.size!==1||sm.get('shared')!==liveData||sm.get('obsolete')!==undefined)throw Error('stale cleanup deleted replacement');
        \\if(debugCalls.length!==1||!debugCalls[0].endsWith('obsolete'))throw Error('stale key logged');
    );
}

test "native source map cache finalization reads the original mutable keys array without copying it" {
    var f = try Fixture.init(); defer f.deinit();
    try f.run(
        \\globalThis.sm=new Cache();globalThis.keys=['before','removed'];
        \\{const module={};sm.set(keys,{},module)}keys[0]='removed';keys.length=1;
    );
    f.checkpoint(); _ = try f.drain();
    try f.run(
        \\if(sm.size!==1||sm.get('before')!==undefined||[...sm].length!==0)throw Error('held keys copied');
        \\if(debugCalls.length!==1||!debugCalls[0].endsWith('removed'))throw Error('held keys mutation ignored');
    );
}
test "native source map cache cleanup interpolates keys and resolves debug callee before coercion" {
    var f = try Fixture.init(); defer f.deinit();
    try f.run(
        \\globalThis.order=[];globalThis.debuglogFixture=function(name,assign){
        \\  globalThis.assignNewDebug=assign;return function(message){order.push('old:'+message)}
        \\};
    );
    try f.createClass("OrderedCache");
    try f.run(
        \\globalThis.sm=new OrderedCache();globalThis.key={ [Symbol.toPrimitive](hint){
        \\  order.push('coerce:'+hint);assignNewDebug(message=>order.push('new:'+message));return 'coerced';
        \\}};
        \\{const module={};sm.set([key,'following'],{},module)}
    );
    f.checkpoint(); _ = try f.drain();
    try f.run(
        \\if(order.length!==3||order[0]!=='coerce:string'||order[1]!=='old:Cleanup obsolete source map cache entry with key: coerced'||order[2]!=='new:Cleanup obsolete source map cache entry with key: following'||sm.size!==0)throw Error('debug callee or ToString ordering '+order);
    );
}
test "native source map cache disabled logging still coerces keys and ordinary logging failure prevents deletion" {
    var f = try Fixture.init(); defer f.deinit();
    try f.run(
        \\globalThis.calls=0;globalThis.coercions=0;globalThis.logReason={};
        \\globalThis.debuglogFixture=function(){return function(){calls++;throw logReason}};
    );
    try f.createClass("ThrowingCache");
    try f.run(
        \\globalThis.sm=new ThrowingCache();globalThis.key={toString(){coercions++;return 'throwing'}};
        \\{const module={};sm.set([key],{},module)}
    );
    f.checkpoint();
    try std.testing.expectError(error.JavaScriptException, f.engine.runReadyJobs(256));
    const caught = try f.takeReason(); defer f.engine.freeValue(caught);
    const expected = try f.global("logReason"); defer f.engine.freeValue(expected);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, caught, expected));
    try f.run("if(calls!==1||coercions!==1||sm.size!==1||sm.get(key)!==undefined)throw Error('throw/delete order');");
    // An explicitly disabled collaborator remains a real callable invocation.
    try f.run("globalThis.debuglogFixture=function(){return function(){calls++}};");
    try f.createClass("DisabledCache");
    try f.run("globalThis.disabled=new DisabledCache();{const module={};disabled.set([key],{},module)}");
    f.checkpoint(); _ = try f.drain();
    try f.run("if(calls!==2||coercions!==2||disabled.size!==0)throw Error('disabled interpolation skipped');");
}
test "native source map cache logger reentry precedes the original unconditional stale entry delete" {
    var f = try Fixture.init(); defer f.deinit();
    try f.run(
        \\globalThis.sizes=[];globalThis.replacementModule={};globalThis.replacementData={};
        \\globalThis.debuglogFixture=function(){return function(){
        \\  sizes.push(sm.size);sm.set(['key'],replacementData,replacementModule);sizes.push(sm.size);
        \\  if(sm.get('key')!==replacementData)throw Error('replacement not visible within debug');
        \\}};
    );
    try f.createClass("ReentrantCache");
    try f.run("globalThis.sm=new ReentrantCache();{const module={};sm.set(['key'],{},module)}");
    f.checkpoint(); _ = try f.drain();
    try f.run("if(sizes.join(',')!=='1,1'||sm.size!==0||sm.get('key')!==undefined)throw Error('debug reentry delete order');");
}
test "native source map cache iterator is an ordinary own next object with live Map order and recursive dead skips" {
    var f = try Fixture.init(); defer f.deinit();
    try f.run(
        \\globalThis.sm=new Cache();globalThis.bModule={};globalThis.cModule={};globalThis.dModule={};
        \\globalThis.bData={b:true};globalThis.cData={c:true};globalThis.dData={d:true};
        \\{const dead={};sm.set(['dead'],{},dead)}
        \\sm.set(['b'],bData,bModule);sm.set(['c'],cData,cModule);
        \\globalThis.it=sm[Symbol.iterator]();globalThis.originalNext=it.next;
        \\if(Object.getPrototypeOf(it)!==Object.prototype||Object.getOwnPropertyNames(it).join(',')!=='next'||Object.getOwnPropertySymbols(it)[0]!==Symbol.iterator)throw Error('iterator prototype or keys');
        \\for(const k of ['next',Symbol.iterator]){const d=Object.getOwnPropertyDescriptor(it,k);if(!d.enumerable||!d.configurable||!d.writable||Object.hasOwn(d.value,'prototype'))throw Error('iterator method descriptor')}
        \\if(it[Symbol.iterator]()!==it||it[Symbol.iterator].call(7)!==7||originalNext.name!=='next'||originalNext.length!==0)throw Error('iterator method receiver');
        \\it.next=function(){throw Error('public next replacement must not redirect captured recursion')};
    );
    f.checkpoint(); // Do not drain: next must skip the actual dead WeakRef.
    try f.run(
        \\const first=originalNext.call(null);
        \\if(first.done||first.value[0]!=='b'||first.value[1]!==bData||Object.keys(first).join(',')!=='done,value')throw Error('recursive skip/first result');
        \\for(const k of ['done','value']){const d=Object.getOwnPropertyDescriptor(first,k);if(!d.enumerable||!d.configurable||!d.writable)throw Error('ordinary result descriptor')}
        \\sm.set(['b'],dData,bModule);sm.set(['d'],dData,dModule);
        \\const second=originalNext(),third=originalNext(),done=originalNext();
        \\if(second.value[0]!=='c'||second.value[1]!==cData||third.value[0]!=='d'||third.value[1]!==dData||!done.done||done.value!==undefined)throw Error('live iterator order');
        \\sm.set(['late'],{},{});if(!originalNext().done)throw Error('exhausted Map iterator reopened');
    );
    _ = try f.drain();
}
test "native source map cache escaped iterator does not keep module or data alive through the cache" {
    var f = try Fixture.init(); defer f.deinit();
    var target_probe: Probe = .{ .engine = f.engine, .first = c.pi_js_undefined() };
    var data_probe: Probe = .{ .engine = f.engine, .first = c.pi_js_undefined() };
    try f.publishProbe("iteratorModule", &target_probe); try f.publishProbe("iteratorData", &data_probe);
    try f.run(
        \\{const sm=new Cache();sm.set(['only'],iteratorData,iteratorModule);globalThis.escaped=sm[Symbol.iterator]()}
        \\delete globalThis.iteratorModule;delete globalThis.iteratorData;
    );
    f.checkpoint();
    try std.testing.expectEqual(@as(usize, 1), target_probe.retired); try std.testing.expectEqual(@as(usize, 1), data_probe.retired);
    try f.run("if(!escaped.next().done)throw Error('escaped iterator retained weak target');");
    _ = try f.drain();
}
test "native source map cache pristine operations survive replaced globals and poisoned live prototypes" {
    var f = try Fixture.init(); defer f.deinit();
    try f.run(
        \\globalThis.SavedObject=Object;globalThis.SavedSymbol=Symbol;globalThis.RealError=Error;
        \\const fail=()=>{throw new RealError('mutable intrinsic reached')};
        \\Map.prototype.get=fail;Map.prototype.set=fail;Map.prototype.delete=fail;Map.prototype.entries=fail;
        \\Object.defineProperty(Map.prototype,'size',{get:fail,configurable:true});
        \\Object.getPrototypeOf(new Map()[Symbol.iterator]()).next=fail;
        \\WeakRef.prototype.deref=fail;FinalizationRegistry.prototype.register=fail;Array.prototype.forEach=fail;Object.freeze=fail;
        \\globalThis.Map=fail;globalThis.WeakRef=fail;globalThis.FinalizationRegistry=fail;globalThis.Array=fail;globalThis.Object=fail;globalThis.Symbol=fail;
    );
    try f.createClass("CapturedCache");
    try f.run(
        \\globalThis.sm=new CapturedCache();globalThis.module={};globalThis.data={};
        \\sm.set(['x'],data,module);if(sm.get('x')!==data||sm.size!==1||!SavedObject.isFrozen(CapturedCache.prototype))throw new RealError('pristine owner');
        \\const it=sm[SavedSymbol.iterator]();if(it.next().value[1]!==data||!it.next().done)throw new RealError('pristine iterator');
        \\delete globalThis.module;delete globalThis.data;
    );
    f.checkpoint(); _ = try f.drain();
    try f.run("if(sm.size!==0||debugCalls.length!==1)throw new RealError('pristine finalization');");
}
test "native source map cache current native producer during key coercion prevents debug and deletion" {
    var f = try Fixture.init(); defer f.deinit();
    const producer = try f.engine.checked(c.JS_NewCFunction(f.engine.context, rawTakenFatal, "sourceMapNativeFatal", 0));
    defer f.engine.freeValue(producer); try f.publish("sourceMapNativeFatal", producer);
    try f.run(
        \\globalThis.sm=new Cache();globalThis.key={toString(){sourceMapNativeFatal();return 'never'}};
        \\{const module={};sm.set([key],{},module)}
    );
    f.checkpoint();
    try std.testing.expectError(error.JavaScriptException, f.engine.runReadyJobs(256));
    const reason = try f.takeReason(); defer f.engine.freeValue(reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try f.run("if(debugCalls.length!==0||sm.size!==1||sm.get(key)!==undefined)throw Error('native fatal was swallowed');");
    try f.balanced();
}
test "native source map cache private data retirement publishes replacement before the retained first fatal" {
    var f = try Fixture.init(); defer f.deinit();
    var probe: Probe = .{ .engine = f.engine, .first = c.pi_js_undefined() };
    defer { probe.emit_fatal=false; f.engine.freeValue(probe.first); }
    try f.publishProbe("oldPayload", &probe);
    try f.run(
        \\globalThis.sm=new Cache();globalThis.module={};globalThis.nextPayload={};
        \\sm.set(['first'],oldPayload,module);delete globalThis.oldPayload;
    );
    probe.emit_fatal=true;
    try std.testing.expectError(error.JavaScriptException, f.run("sm.set(['next'],nextPayload,module);"));
    const reason = try f.takeReason(); defer f.engine.freeValue(reason);
    try std.testing.expectEqual(@as(usize, 1), probe.retired);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, reason, probe.first));
    try f.run("if(sm.size!==2||sm.get('first')!==nextPayload||sm.get('next')!==nextPayload)throw Error('private replacement was rolled back');");
    try f.balanced();
}
test "native source map cache debug binding keeps original initialization TDZ and captured flagged data nonfatal" {
    var f = try Fixture.init(); defer f.deinit();
    try f.run("globalThis.debuglogFixture=function(name,assign){assign(function(){});return function(){}};");
    const logger = try f.global("debuglogFixture"); defer f.engine.freeValue(logger);
    try std.testing.expectError(error.JavaScriptException, cache_owner.create(f.engine, .{ .debuglog = logger }));
    const tdz = try f.takeReason(); defer f.engine.freeValue(tdz); try f.publish("tdzReason",tdz);
    try f.run("if(!(tdzReason instanceof ReferenceError))throw Error('debug lexical TDZ');");
    const flagged = try f.engine.checked(c.JS_NewError(f.engine.context)); defer f.engine.freeValue(flagged);
    c.JS_SetUncatchableError(f.engine.context,flagged); try f.publish("flaggedData",flagged);
    try f.run("globalThis.debuglogFixture=function(){return function(){return flaggedData}};");
    try f.createClass("DataCache");
    try f.run(
        \\globalThis.sm=new DataCache();globalThis.module={};sm.set(['live'],flaggedData,module);
        \\if(sm.get('live')!==flaggedData)throw Error('flagged data rejected');delete globalThis.module;
    );
    f.checkpoint(); _ = try f.drain();
    try f.run("if(sm.size!==0)throw Error('logger returned data promoted to pending');"); try f.balanced();
}

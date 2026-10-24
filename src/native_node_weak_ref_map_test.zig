//! Actual-VM controls for diagnostics_channel WeakRefMap and own-private Get.
//! Root owns fresh native compilation, metadata and execution.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const map_owner = @import("extensions/native_node_weak_ref_map.zig");
const weak_owner = @import("extensions/native_node_weak_reference.zig");
const collections = @import("extensions/native_node_fs_collections.zig");
const js = @import("extensions/native_js_values.zig");

const Fixture = struct {
    engine: *em.Engine,
    fn init() !Fixture {
        const engine = try em.Engine.init(std.testing.allocator, .{});
        errdefer engine.deinit();
        var f: Fixture = .{ .engine = engine };
        const weak_class = try weak_owner.create(engine);
        defer engine.freeValue(weak_class);
        try f.publish("NativeWeakReference", weak_class);
        try f.createClass("NativeWeakRefMap", weak_class);
        return f;
    }
    fn deinit(self: *Fixture) void { self.engine.deinit(); }
    fn eval(self: *Fixture, source: []const u8) !c.JSValue {
        return self.engine.eval(source, "native-weak-ref-map-control.js", c.JS_EVAL_TYPE_GLOBAL);
    }
    fn run(self: *Fixture, source: []const u8) !void {
        self.engine.freeValue(try self.eval(source));
    }
    fn check(self: *Fixture, source: []const u8) !void {
        const value = try self.eval(source); defer self.engine.freeValue(value);
        try std.testing.expect(c.JS_IsStrictEqual(self.engine.context, value,
            c.JS_NewBool(self.engine.context, true)));
    }
    fn global(self: *Fixture, name: [*:0]const u8) !c.JSValue {
        const object = c.JS_GetGlobalObject(self.engine.context);
        defer self.engine.freeValue(object);
        return self.engine.checked(c.JS_GetPropertyStr(self.engine.context, object, name));
    }
    fn publish(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        const object = c.JS_GetGlobalObject(self.engine.context);
        defer self.engine.freeValue(object);
        if (c.JS_DefinePropertyValueStr(self.engine.context, object, name,
            c.JS_DupValue(self.engine.context, value), c.JS_PROP_C_W_E) < 0)
            return js.capture(self.engine);
    }
    fn createClass(self: *Fixture, name: [*:0]const u8, weak_class: c.JSValue) !void {
        const constructor_value = try map_owner.create(self.engine, .{ .weak_reference = weak_class });
        defer self.engine.freeValue(constructor_value);
        try self.publish(name, constructor_value);
    }
    fn checkpoint(self: *Fixture) void {
        self.engine.finishJob();
        c.JS_RunGC(self.engine.runtime);
    }
    fn drain(self: *Fixture) !usize {
        const count = try self.engine.runReadyJobs(256);
        try std.testing.expect(!c.JS_IsJobPending(self.engine.runtime));
        self.engine.finishJob();
        return count;
    }
    fn takeReason(self: *Fixture) !c.JSValue {
        if (c.JS_HasException(self.engine.context)) return c.JS_GetException(self.engine.context);
        if (self.engine.captured_exception) |reason| {
            self.engine.captured_exception = null;
            return reason;
        }
        return error.ActualWeakRefMapFailureRequired;
    }
};
const PrivateRead = struct { value: c.JSValue, found: c_int };
fn readPrivate(engine: *em.Engine, receiver: c.JSValue, key: c.JSValue) !PrivateRead {
    var found: c_int = -1;
    const value = try engine.checked(c.JS_PiGetOwnPrivateProperty(
        engine.context, receiver, key, &found));
    return .{ .value = value, .found = found };
}
fn setPrivate(engine: *em.Engine, receiver: c.JSValue,
    key: c.JSValue, value: c.JSValue) !void
{
    if (c.JS_PiSetPrivateProperty(engine.context, receiver, key,
        c.JS_DupValue(engine.context, value)) < 0) return js.capture(engine);
}
fn rawTakenFatal(context: ?*c.JSContext, _: c.JSValue,
    _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const engine = em.Engine.fromContext(context.?);
    _ = engine.throwNativeOutOfMemoryFatal();
    if (c.JS_HasException(engine.context)) engine.freeValue(c.JS_GetException(engine.context));
    return c.pi_js_undefined();
}

test "native WeakRefMap original class metadata and genuine SafeMap storage" {
    var f = try Fixture.init(); defer f.deinit();
    try f.check(
        \\(()=>{const C=NativeWeakRefMap,p=C.prototype,S=Object.getPrototypeOf(C),m=new C;
        \\if(C.name!=="WeakRefMap"||C.length!==0||S.name!=="SafeMap"||
        \\Object.getPrototypeOf(p)!==S.prototype||Object.getPrototypeOf(S.prototype)!==null||
        \\!Object.isFrozen(S)||!Object.isFrozen(S.prototype))return false;
        \\if(Reflect.ownKeys(p).join("|")!=="constructor|set|get|has|incRef|decRef")return false;
        \\for(const [n,l]of [["set",2],["get",1],["has",1],["incRef",1],["decRef",1]]){
        \\const d=Object.getOwnPropertyDescriptor(p,n);if(!d.writable||d.enumerable||!d.configurable||
        \\d.value.name!==n||d.value.length!==l||Object.hasOwn(d.value,"prototype"))return false}
        \\const pd=Object.getOwnPropertyDescriptor(C,"prototype");
        \\return !pd.writable&&!pd.enumerable&&!pd.configurable&&m instanceof C&&m instanceof S&&
        \\Object.prototype.toString.call(m)==="[object Map]"&&m.size===0&&Reflect.ownKeys(m).length===0})()
    );
}
test "native WeakRefMap real SafeFinalizationRegistry acquisition is cached frozen and branded" {
    var f = try Fixture.init(); defer f.deinit();
    const first = try collections.acquireSafeFinalizationRegistry(f.engine);
    defer f.engine.freeValue(first);
    const second = try collections.acquireSafeFinalizationRegistry(f.engine);
    defer f.engine.freeValue(second);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, first, second));
    try f.publish("SafeFR", first);
    try f.check(
        \\(()=>{const p=SafeFR.prototype,r=new SafeFR(()=>{}),target={};
        \\r.register(target,"held");let rejected=false;try{r.register(3,"held")}catch(e){rejected=e instanceof TypeError}
        \\return SafeFR.name==="SafeFinalizationRegistry"&&SafeFR.length===0&&
        \\Object.isFrozen(SafeFR)&&Object.isFrozen(p)&&Object.getPrototypeOf(p)===null&&
        \\Object.getPrototypeOf(SafeFR)===FinalizationRegistry&&
        \\Object.prototype.toString.call(r)==="[object FinalizationRegistry]"&&rejected})()
    );
}
test "native WeakRefMap set get has and original Number refcount transitions" {
    var f = try Fixture.init(); defer f.deinit();
    try f.check(
        \\(()=>{const m=new NativeWeakRefMap,a={},b={};return m.set("a",a)===m&&
        \\m.set("b",b)===m&&m.size===2&&m.get("a")===a&&m.has("b")&&
        \\m.incRef("a")===1&&m.incRef("a")===2&&m.decRef("a")===1&&m.decRef("a")===0&&
        \\m.decRef("a")===-1&&m.incRef("a")===0&&m.incRef("a")===1&&m.get("b")===b})()
    );
}
test "native WeakRefMap registration rejects invalid targets and same held value before weak construction" {
    var f = try Fixture.init(); defer f.deinit();
    try f.run(
        \\globalThis.constructs=0;globalThis.ObservedWeak=new Proxy(NativeWeakReference,{
        \\construct(t,a,n){constructs++;return Reflect.construct(t,a,n)}});
    );
    const observed = try f.global("ObservedWeak"); defer f.engine.freeValue(observed);
    try f.createClass("ObservedMap", observed);
    try f.check(
        \\(()=>{const m=new ObservedMap;for(const v of [undefined,null,1,"x",true,1n,Symbol.for("registered")]){
        \\let rejected=false;try{m.set("k",v)}catch(e){rejected=e instanceof TypeError}if(!rejected)return false}
        \\const same={};let rejected=false;try{m.set(same,same)}catch(e){rejected=e instanceof TypeError}
        \\return rejected&&constructs===0&&m.size===0})()
    );
}
test "native WeakRefMap missing keys optional calls and generic Map receivers" {
    var f = try Fixture.init(); defer f.deinit();
    try f.check(
        \\(()=>{const p=NativeWeakRefMap.prototype,m=new Map([["null",null],["undefined",undefined]]);
        \\for(const n of ["get","incRef","decRef"])for(const k of ["missing","null","undefined"])
        \\if(p[n].call(m,k)!==undefined)return false;
        \\const marker={},wrapper={get(){return marker},incRef(){return 41},decRef(){return -9}};
        \\m.set("value",wrapper);return p.get.call(m,"value")===marker&&p.has.call(m,"value")&&
        \\p.incRef.call(m,"value")===41&&p.decRef.call(m,"value")===-9})()
    );
}
test "native WeakRefMap has reads live this get and applies original truthiness" {
    var f = try Fixture.init(); defer f.deinit();
    try f.check(
        \\(()=>{const p=NativeWeakRefMap.prototype,events=[],receiver={get get(){events.push("get");
        \\return function(k){events.push(this===receiver&&k==="key");return {}}}};
        \\if(!p.has.call(receiver,"key")||events.join("|")!=="get|true")return false;
        \\for(const value of [undefined,null,false,0,"",NaN])if(p.has.call({get(){return value}},"x"))return false;
        \\return true})()
    );
}
test "native WeakRefMap constructor and methods preserve nonconstructible and new requirements" {
    var f = try Fixture.init(); defer f.deinit();
    try f.check(
        \\(()=>{let count=0;try{NativeWeakRefMap()}catch(e){if(e instanceof TypeError)count++}
        \\for(const n of ["set","get","has","incRef","decRef"])
        \\try{Reflect.construct(NativeWeakRefMap.prototype[n],[])}catch(e){if(e instanceof TypeError)count++}
        \\return count===6})()
    );
}
test "native WeakRefMap set private brand rejects proxies and inherited brands without traps" {
    var f = try Fixture.init(); defer f.deinit();
    try f.check(
        \\(()=>{const m=new NativeWeakRefMap;let traps=0;
        \\const p=new Proxy(m,new Proxy({},{get(){traps++;throw Error("trap")}}));
        \\const revoked=Proxy.revocable(m,{});revoked.revoke();
        \\for(const receiver of [undefined,null,1,"x",{},Object.create(m),p,revoked.proxy]){
        \\let rejected=false;try{NativeWeakRefMap.prototype.set.call(receiver,"k",{})}
        \\catch(e){rejected=e instanceof TypeError}if(!rejected)return false}
        \\return traps===0&&m.size===0})()
    );
}
test "native WeakRefMap separate class evaluations keep distinct private brands" {
    var f = try Fixture.init(); defer f.deinit();
    const weak_class = try f.global("NativeWeakReference"); defer f.engine.freeValue(weak_class);
    try f.createClass("OtherMap", weak_class);
    try f.check(
        \\(()=>{const a=new NativeWeakRefMap,b=new OtherMap,value={};b.set("k",value);
        \\let rejected=false;try{NativeWeakRefMap.prototype.set.call(b,"k",{})}catch(e){rejected=e instanceof TypeError}
        \\return rejected&&NativeWeakRefMap.prototype.get.call(b,"k")===value&&
        \\Object.getPrototypeOf(NativeWeakRefMap)===Object.getPrototypeOf(OtherMap)&&a.size===0})()
    );
}
test "native WeakRefMap derived new target and live superclass retain actual arguments" {
    var f = try Fixture.init(); defer f.deinit();
    try f.check(
        \\(()=>{class Child extends NativeWeakRefMap{};const child=new Child([]),value={};child.set("k",value);
        \\const C=NativeWeakRefMap,base=Object.getPrototypeOf(C),events=[];
        \\Object.setPrototypeOf(C,new Proxy(base,{construct(t,args,n){events.push(args.length,args[0],n);
        \\return Reflect.construct(t,args,n)}}));const empty=[];const made=Reflect.construct(C,[empty,37],Child);
        \\return child instanceof Child&&child.get("k")===value&&made instanceof Child&&
        \\events[0]===2&&events[1]===empty&&events[2]===Child})()
    );
}
test "native WeakRefMap nonempty Map iterable calls set before private field initialization and closes iterator" {
    var f = try Fixture.init(); defer f.deinit();
    try f.check(
        \\(()=>{let closes=0,steps=0;const iterable={[Symbol.iterator](){return{
        \\next(){steps++;return {done:false,value:["k",{}]}},return(){closes++;return {done:true}}}}};
        \\let rejected=false;try{new NativeWeakRefMap(iterable)}catch(e){rejected=e instanceof TypeError}
        \\return rejected&&steps===1&&closes===1&&new NativeWeakRefMap([]).size===0})()
    );
}
test "native WeakRefMap super get uses live home base and actual getter receiver" {
    var f = try Fixture.init(); defer f.deinit();
    try f.check(
        \\(()=>{const C=NativeWeakRefMap,p=C.prototype,m=new C,events=[],wrapper={get(){events.push(this===wrapper);return 73}};
        \\const parent=new Proxy({get get(){events.push(this===m);return function(k){
        \\events.push(this===m,k);return wrapper}}},{get(t,k,r){events.push(k,r===m);return Reflect.get(t,k,r)}});
        \\Object.setPrototypeOf(p,parent);return m.get("key")===73&&
        \\events.join("|")==="get|true|true|true|key|true"})()
    );
}
test "native WeakRefMap super set is resolved before WeakReference construction" {
    var f = try Fixture.init(); defer f.deinit();
    try f.run(
        \\globalThis.events=[];globalThis.WrappedWeak=new Proxy(NativeWeakReference,{construct(t,a,n){
        \\events.push("weak");globalThis.parent.set=function(){throw Error("late callee")};
        \\return Reflect.construct(t,a,n)}});
    );
    const wrapped = try f.global("WrappedWeak"); defer f.engine.freeValue(wrapped);
    try f.createClass("ObservedMap", wrapped);
    try f.check(
        \\(()=>{const p=ObservedMap.prototype,m=new ObservedMap,value={},sentinel={};
        \\globalThis.parent=Object.create(Object.getPrototypeOf(p));
        \\Object.defineProperty(parent,"set",{configurable:true,get(){events.push("callee");
        \\return function(k,w){events.push(this===m,k,w.get()===value);return sentinel}},
        \\set(v){events.push("replace")}});
        \\Object.setPrototypeOf(p,parent);return m.set("key",value)===sentinel&&
        \\events.join("|")==="callee|weak|replace|true|key|true"})()
    );
}
test "native WeakRefMap registration survives a later actual weak constructor throw" {
    var f = try Fixture.init(); defer f.deinit();
    try f.run(
        \\globalThis.reason={};globalThis.ThrowingWeak=new Proxy(NativeWeakReference,{construct(){throw reason}});
    );
    const throwing = try f.global("ThrowingWeak"); defer f.engine.freeValue(throwing);
    try f.createClass("ThrowingMap", throwing);
    try f.run(
        \\globalThis.m=new ThrowingMap;globalThis.cleanups=0;
        \\m.has=function(k){if(k!=="registered")throw Error("held key");cleanups++;return false};
        \\{const target={};try{m.set("registered",target)}catch(e){if(e!==reason)throw e}}
        \\if(m.size!==0)throw Error("failed set inserted");
    );
    f.checkpoint();
    try std.testing.expect((try f.drain()) > 0);
    try f.check("cleanups===1&&m.size===0");
}

test "native WeakRefMap dead target remains an entry until genuine finalization cleanup" {
    var f = try Fixture.init(); defer f.deinit();
    try f.run(
        \\globalThis.m=new NativeWeakRefMap;
        \\{const target={};target.self=target;m.set("dead",target)}
    );
    f.checkpoint();
    try f.check("m.size===1&&m.get('dead')===undefined&&!m.has('dead')");
    try std.testing.expect((try f.drain()) > 0);
    try f.check("m.size===0&&m.get('dead')===undefined");
}
test "native WeakRefMap zero refcount can strengthen again before target collection" {
    var f = try Fixture.init(); defer f.deinit();
    try f.run(
        \\globalThis.m=new NativeWeakRefMap;
        \\{const target={marker:81};target.self=target;m.set("live",target);m.incRef("live")}
    );
    f.checkpoint(); _ = try f.drain();
    try f.check(
        \\m.size===1&&m.get("live").marker===81&&m.decRef("live")===0&&m.size===1&&m.incRef("live")===1
    );
    f.checkpoint(); _ = try f.drain();
    try f.check("m.get('live').marker===81&&m.decRef('live')===0");
    f.checkpoint(); _ = try f.drain();
    try f.check("m.size===0");
}
test "native WeakRefMap stale registration keeps a live replacement for the same key" {
    var f = try Fixture.init(); defer f.deinit();
    try f.run(
        \\globalThis.m=new NativeWeakRefMap;globalThis.live={marker:83};
        \\{const old={};old.self=old;m.set("shared",old);m.set("old",old);m.set("shared",live)}
    );
    f.checkpoint(); _ = try f.drain();
    try f.check("m.size===1&&m.get('shared')===live&&m.get('old')===undefined");
}
test "native WeakRefMap cleanup observes live has then delete with lexical receiver and held key" {
    var f = try Fixture.init(); defer f.deinit();
    try f.run(
        \\globalThis.m=new NativeWeakRefMap;globalThis.events=[];globalThis.held={marker:89};
        \\{const target={};target.self=target;m.set(held,target)}
        \\Object.defineProperty(m,"has",{get(){events.push("has:get");return function(k){
        \\events.push(this===m,k===held);return false}}});
        \\Object.defineProperty(m,"delete",{get(){events.push("delete:get");return function(k){
        \\events.push(this===m,k===held);return Map.prototype.delete.call(this,k)}}});
    );
    f.checkpoint(); _ = try f.drain();
    try f.check(
        \\events.join("|")==="has:get|true|true|delete:get|true|true"&&m.size===0
    );
}
test "native WeakRefMap cleanup truthy live has result suppresses delete lookup" {
    var f = try Fixture.init(); defer f.deinit();
    try f.run(
        \\globalThis.m=new NativeWeakRefMap;globalThis.hasCalls=0;globalThis.deleteReads=0;
        \\{const target={};target.self=target;m.set("dead",target)}
        \\m.has=function(){hasCalls++;return {}};
        \\Object.defineProperty(m,"delete",{get(){deleteReads++;throw Error("unreachable delete")}});
    );
    f.checkpoint(); _ = try f.drain();
    try f.check("hasCalls===1&&deleteReads===0&&m.size===1");
}
test "native WeakRefMap actual Map key identity includes NaN signed zero symbols and objects" {
    var f = try Fixture.init(); defer f.deinit();
    try f.check(
        \\(()=>{const m=new NativeWeakRefMap,a={},b={},key={},sym=Symbol("key");
        \\m.set(NaN,a).set(-0,a).set(key,a).set(sym,a).set(undefined,b);
        \\m.set(+0,b);return m.size===5&&m.get(Number("bad"))===a&&m.get(0)===b&&
        \\m.get(key)===a&&m.get({})===undefined&&m.get(sym)===a&&m.get()===b})()
    );
}
test "native WeakRefMap private initialization supports frozen returned objects and rejects duplicate stamping" {
    var f = try Fixture.init(); defer f.deinit();
    try f.check(
        \\(()=>{const C=NativeWeakRefMap,receiver=Object.freeze(new Map),value={};
        \\Object.setPrototypeOf(C,function(){return receiver});const first=new C;
        \\if(first!==receiver||C.prototype.set.call(first,"k",value)!==receiver||
        \\C.prototype.get.call(first,"k")!==value||Object.isExtensible(first))return false;
        \\let rejected=false;try{new C}catch(e){rejected=e instanceof TypeError&&
        \\e.message==="Cannot initialize #finalizers twice on the same object"}
        \\return rejected&&Reflect.ownKeys(receiver).length===0})()
    );
}
test "native WeakRefMap private brand can belong to a returned Proxy wrapper without forwarding to its target" {
    var f = try Fixture.init(); defer f.deinit();
    try f.check(
        \\(()=>{const C=NativeWeakRefMap,target={},proxy=new Proxy(target,{});
        \\Object.setPrototypeOf(C,function(){return proxy});const made=new C;
        \\let reachedSuper=false;const home=C.prototype;Object.setPrototypeOf(home,{set(k,w){
        \\reachedSuper=this===proxy&&k==="k"&&w.get()===value;return this}});
        \\const value={};if(C.prototype.set.call(made,"k",value)!==proxy||!reachedSuper)return false;
        \\let targetRejected=false;try{C.prototype.set.call(target,"k",value)}catch(e){targetRejected=e instanceof TypeError}
        \\return targetRejected&&Reflect.ownKeys(target).length===0})()
    );
}
test "native WeakRefMap real registry callback cycle does not retain an unreachable map" {
    var f = try Fixture.init(); defer f.deinit();
    try f.run(
        \\globalThis.target={};
        \\{const m=new NativeWeakRefMap;m.set("key",target);globalThis.mapRef=new WeakRef(m)}
    );
    f.checkpoint(); _ = try f.drain();
    try f.check("mapRef.deref()===undefined&&typeof target==='object'");
}
test "native WeakRefMap completed primordial captures ignore later public constructor and method replacements" {
    var f = try Fixture.init(); defer f.deinit();
    try f.run(
        \\globalThis.calls=0;const fail=function(){calls++;throw Error("public mutation")};
        \\Map.prototype.set=fail;Map.prototype.get=fail;FinalizationRegistry.prototype.register=fail;
        \\WeakRef.prototype.deref=fail;globalThis.Map=fail;globalThis.FinalizationRegistry=fail;globalThis.WeakRef=fail;
    );
    try f.check(
        \\(()=>{const m=new NativeWeakRefMap,value={};return m.set("k",value)===m&&
        \\m.get("k")===value&&m.incRef("k")===1&&m.decRef("k")===0&&calls===0})()
    );
}
test "native WeakRefMap own private getter distinguishes absence undefined and inherited private storage" {
    var f = try Fixture.init(); defer f.deinit();
    const key = try f.engine.checked(c.JS_NewPrivateSymbol(f.engine.context, "control"));
    defer f.engine.freeValue(key);
    const parent = try f.engine.checked(c.JS_NewObject(f.engine.context));
    defer f.engine.freeValue(parent);
    const child = try f.engine.checked(c.JS_NewObjectProto(f.engine.context, parent));
    defer f.engine.freeValue(child);
    const absent = try readPrivate(f.engine, child, key); defer f.engine.freeValue(absent.value);
    try std.testing.expectEqual(@as(c_int, 0), absent.found);
    try std.testing.expect(c.JS_IsUndefined(absent.value));
    try setPrivate(f.engine, parent, key, c.pi_js_undefined());
    const own = try readPrivate(f.engine, parent, key); defer f.engine.freeValue(own.value);
    try std.testing.expectEqual(@as(c_int, 1), own.found);
    try std.testing.expect(c.JS_IsUndefined(own.value));
    const inherited = try readPrivate(f.engine, child, key); defer f.engine.freeValue(inherited.value);
    try std.testing.expectEqual(@as(c_int, 0), inherited.found);
    try std.testing.expect(c.JS_IsUndefined(inherited.value));
}
test "native WeakRefMap own private getter bypasses absent Proxy traps and reads revoked wrapper storage" {
    var f = try Fixture.init(); defer f.deinit();
    try f.run(
        \\globalThis.traps=0;globalThis.target={};
        \\globalThis.pair=Proxy.revocable(target,new Proxy({},{get(){traps++;throw Error("trap")}}));
        \\globalThis.proxy=pair.proxy;
    );
    const proxy = try f.global("proxy"); defer f.engine.freeValue(proxy);
    const target = try f.global("target"); defer f.engine.freeValue(target);
    const key = try f.engine.checked(c.JS_NewPrivateSymbol(f.engine.context, "control"));
    defer f.engine.freeValue(key);
    try setPrivate(f.engine, target, key, c.JS_NewInt32(f.engine.context, 7));
    const absent = try readPrivate(f.engine, proxy, key); defer f.engine.freeValue(absent.value);
    try std.testing.expectEqual(@as(c_int, 0), absent.found);
    try setPrivate(f.engine, proxy, key, c.JS_NewInt32(f.engine.context, 13));
    try f.run("pair.revoke()");
    const own = try readPrivate(f.engine, proxy, key); defer f.engine.freeValue(own.value);
    try std.testing.expectEqual(@as(c_int, 1), own.found);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, own.value, c.JS_NewInt32(f.engine.context, 13)));
    const original = try readPrivate(f.engine, target, key); defer f.engine.freeValue(original.value);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, original.value, c.JS_NewInt32(f.engine.context, 7)));
    try f.check("traps===0&&Reflect.ownKeys(target).length===0");
}
test "native WeakRefMap own private getter rejects public keys and primitive receivers with actual TypeError" {
    var f = try Fixture.init(); defer f.deinit();
    const object = try f.engine.checked(c.JS_NewObject(f.engine.context));
    defer f.engine.freeValue(object);
    const private_key = try f.engine.checked(c.JS_NewPrivateSymbol(f.engine.context, "control"));
    defer f.engine.freeValue(private_key);
    const public_key = try f.eval("Symbol('public')"); defer f.engine.freeValue(public_key);
    const string_key = try f.eval("'control'"); defer f.engine.freeValue(string_key);
    const bad = [_][2]c.JSValue{
        .{object, public_key}, .{object, string_key}, .{c.pi_js_null(), private_key},
        .{c.JS_NewInt32(f.engine.context, 1), private_key},
    };
    for (bad) |pair| {
        try std.testing.expectError(error.JavaScriptException, readPrivate(f.engine, pair[0], pair[1]));
        const reason = try f.takeReason(); defer f.engine.freeValue(reason);
        try f.publish("actualReason", reason);
        try f.check("actualReason instanceof TypeError");
    }
}
test "native WeakRefMap own private accessor preserves receiver and exact throw without exotic fallback" {
    var f = try Fixture.init(); defer f.deinit();
    try f.run(
        \\globalThis.marker={};globalThis.receiverSeen=null;globalThis.shouldThrow=false;
        \\globalThis.getter=function(){receiverSeen=this;if(shouldThrow)throw marker;return marker};
    );
    const object = try f.engine.checked(c.JS_NewObject(f.engine.context));
    defer f.engine.freeValue(object);
    const private_key = try f.engine.checked(c.JS_NewPrivateSymbol(f.engine.context, "control"));
    defer f.engine.freeValue(private_key);
    const property = c.JS_ValueToAtom(f.engine.context, private_key);
    try std.testing.expect(property != c.JS_ATOM_NULL);
    defer c.JS_FreeAtom(f.engine.context, property);
    const getter = try f.global("getter"); defer f.engine.freeValue(getter);
    if (c.JS_DefinePropertyGetSet(f.engine.context, object, property,
        c.JS_DupValue(f.engine.context, getter), c.pi_js_undefined(),
        c.JS_PROP_CONFIGURABLE | c.JS_PROP_THROW) < 0) return js.capture(f.engine);
    try f.publish("privateReceiver", object);
    const own = try readPrivate(f.engine, object, private_key); defer f.engine.freeValue(own.value);
    const marker = try f.global("marker"); defer f.engine.freeValue(marker);
    try std.testing.expectEqual(@as(c_int, 1), own.found);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, own.value, marker));
    try f.check("receiverSeen===privateReceiver");
    try f.run("shouldThrow=true");
    try std.testing.expectError(error.JavaScriptException, readPrivate(f.engine, object, private_key));
    const reason = try f.takeReason(); defer f.engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, reason, marker));
}
test "native WeakRefMap ordinary super getter throw preserves the exact reason and avoids later mutation" {
    var f = try Fixture.init(); defer f.deinit();
    try f.check(
        \\(()=>{const C=NativeWeakRefMap,m=new C,reason={};const parent=Object.create(Object.getPrototypeOf(C.prototype));
        \\Object.defineProperty(parent,"set",{get(){throw reason}});Object.setPrototypeOf(C.prototype,parent);
        \\let observed;try{m.set("key",{})}catch(e){observed=e}return observed===reason&&m.size===0})()
    );
}
test "native WeakRefMap flagged returned data remains data across optional get and has" {
    var f = try Fixture.init(); defer f.deinit();
    const flagged = try f.engine.checked(c.JS_NewError(f.engine.context));
    defer f.engine.freeValue(flagged);
    c.JS_SetUncatchableError(f.engine.context, flagged);
    try f.publish("flaggedData", flagged);
    try f.check(
        \\(()=>{const raw=new Map([["key",{get(){return flaggedData}}]]),p=NativeWeakRefMap.prototype;
        \\return p.get.call(raw,"key")===flaggedData&&p.has.call(raw,"key")})()
    );
    try std.testing.expect(!c.JS_HasException(f.engine.context));
    try std.testing.expect(f.engine.native_fatal_invocation == null);
}
test "native WeakRefMap actual taken fatal from live super getter wins before weak construction" {
    var f = try Fixture.init(); defer f.deinit();
    const fatal_function = try f.engine.checked(c.JS_NewCFunction(
        f.engine.context, rawTakenFatal, "rawTakenFatal", 0));
    defer f.engine.freeValue(fatal_function);
    try f.publish("rawTakenFatal", fatal_function);
    try f.run(
        \\globalThis.m=new NativeWeakRefMap;globalThis.after=0;
        \\const parent=Object.create(Object.getPrototypeOf(NativeWeakRefMap.prototype));
        \\Object.defineProperty(parent,"set",{get(){rawTakenFatal();after++;return function(){after++}}});
        \\Object.setPrototypeOf(NativeWeakRefMap.prototype,parent);
    );
    try std.testing.expectError(error.JavaScriptException, f.run("m.set('key',{})"));
    const reason = try f.takeReason(); defer f.engine.freeValue(reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try f.check("m.size===0&&after===0");
    try std.testing.expect(f.engine.native_fatal_invocation == null);
}

const OwnPrivateAccessorProbe = struct {
    private_key: c.JSValue,
    marker: c.JSValue,
    retired: usize = 0,
    retired_during_call: bool = false,
    called: bool = false,
};
fn retireOwnPrivateAccessorProbe(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const probe: *OwnPrivateAccessorProbe = @ptrCast(@alignCast(
        c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    probe.retired += 1;
}
fn selfRemovingOwnPrivateGetter(context: ?*c.JSContext, receiver: c.JSValue,
    _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const ctx = context.?;
    const probe: *OwnPrivateAccessorProbe = @ptrCast(@alignCast(
        c.JS_GetOpaque(data[0], c.JS_GetClassID(data[0])).?));
    probe.called = true;
    const atom = c.JS_ValueToAtom(ctx, probe.private_key);
    if (atom == c.JS_ATOM_NULL) return c.pi_js_exception();
    defer c.JS_FreeAtom(ctx, atom);
    if (c.JS_DeleteProperty(ctx, receiver, atom, c.JS_PROP_THROW) < 0)
        return c.pi_js_exception();
    // The original field was the only external getter root. The accessor call
    // itself must still retain its native data through explicit collection.
    c.JS_RunGC(c.JS_GetRuntime(ctx));
    probe.retired_during_call = probe.retired != 0;
    return c.JS_DupValue(ctx, probe.marker);
}
test "native WeakRefMap own private accessor remains owned when it removes its own field" {
    var f = try Fixture.init(); defer f.deinit();
    const private_key = try f.engine.checked(c.JS_NewPrivateSymbol(f.engine.context, "retiring"));
    defer f.engine.freeValue(private_key);
    const marker = try f.engine.checked(c.JS_NewObject(f.engine.context));
    defer f.engine.freeValue(marker);
    const receiver = try f.engine.checked(c.JS_NewObject(f.engine.context));
    defer f.engine.freeValue(receiver);
    var probe: OwnPrivateAccessorProbe = .{ .private_key = private_key, .marker = marker };
    var id: c.JSClassID = 0;
    if (c.JS_NewClassID(f.engine.runtime, &id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{
        .class_name = "Own private getter lifetime probe",
        .finalizer = retireOwnPrivateAccessorProbe,
    };
    if (c.JS_NewClass(f.engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    {
        const sentinel = try f.engine.checked(c.JS_NewObjectClass(f.engine.context, id));
        defer f.engine.freeValue(sentinel);
        _ = c.JS_SetOpaque(sentinel, &probe);
        const data = [_]c.JSValue{sentinel};
        const getter = try f.engine.checked(c.JS_NewCFunctionData(f.engine.context,
            selfRemovingOwnPrivateGetter, 0, 0, 1, @constCast(&data)));
        const atom = c.JS_ValueToAtom(f.engine.context, private_key);
        if (atom == c.JS_ATOM_NULL) {
            f.engine.freeValue(getter);
            return js.capture(f.engine);
        }
        defer c.JS_FreeAtom(f.engine.context, atom);
        if (c.JS_DefinePropertyGetSet(f.engine.context, receiver, atom, getter,
            c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_THROW) < 0)
            return js.capture(f.engine);
    }
    const observed = try readPrivate(f.engine, receiver, private_key);
    defer f.engine.freeValue(observed.value);
    try std.testing.expectEqual(@as(c_int, 1), observed.found);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, observed.value, marker));
    try std.testing.expect(probe.called and !probe.retired_during_call);
    // No immediate DECREF-finalizer ordering is presumed after the call.
    f.checkpoint();
    try std.testing.expectEqual(@as(usize, 1), probe.retired);
    const absent = try readPrivate(f.engine, receiver, private_key);
    defer f.engine.freeValue(absent.value);
    try std.testing.expectEqual(@as(c_int, 0), absent.found);
}

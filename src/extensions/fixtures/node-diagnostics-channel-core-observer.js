// Actual-VM differential observer for the literal retained Channel core.
// The same real process, SafeMap, WeakReference and argument-error owners are
// supplied to both subjects. The native uncaught-binding probe observes calls;
// this does not claim the unfinished production fatal-report/exit adapter.
"use strict";
globalThis.dcObserve = function(kind) {
  const out = [], refs = [];
  const push = Function.prototype.call.bind(Array.prototype.push);
  const apply = Reflect.apply;
  const inc = WeakReferenceOwner.prototype.incRef;
  const dec = WeakReferenceOwner.prototype.decRef;
  WeakReferenceOwner.prototype.incRef = function() {
    const n = apply(inc, this, []); push(refs, ["inc", n]); return n;
  };
  WeakReferenceOwner.prototype.decRef = function() {
    const n = apply(dec, this, []); push(refs, ["dec", n]); return n;
  };
  const assert = (value, name) => { if (!value) throw Error("channel observer: " + name); };
  const reason = fn => { try { fn(); } catch (e) { return e; } throw Error("expected throw"); };
  const errorView = e => e && e.tag ? {tag:e.tag} :
    {name:e && e.name,code:e && e.code,type:e instanceof TypeError};
  const functionView = fn => [fn.name,fn.length,Object.hasOwn(fn,"prototype")];
  globalThis.dcError = {tag:"original"};
  globalThis.dcFinish = () => {
    const reports = dcReports();
    return {out,refs,reports:reports.map(r=>[errorView(r[0]),r[1],r[2],r[3],r[4]])};
  };
  const channel = D.channel;
  if (kind === "shape") {
    const c=channel("shape"),p=D.Channel.prototype;
    out.push(functionView(D.Channel),functionView(channel),functionView(D.subscribe),
      functionView(D.unsubscribe),functionView(D.hasSubscribers));
    out.push(Reflect.ownKeys(p).map(String));
    out.push(Object.keys(c),c.name,c.hasSubscribers,c instanceof D.Channel);
    for (const name of ["subscribe","unsubscribe","bindStore","unbindStore","publish","runStores"]) {
      const d=Object.getOwnPropertyDescriptor(p,name);
      out.push(name,functionView(d.value),d.writable,d.enumerable,d.configurable);
    }
    const d=Object.getOwnPropertyDescriptor(p,"hasSubscribers");
    out.push(functionView(d.get),d.set===undefined,d.enumerable,d.configurable);
    assert(c._subscribers===undefined&&c._stores===undefined,"inactive fields");
  } else if (kind === "inactive") {
    const c=channel("idle"),marker={},receiver={};
    out.push(c.publish(1),c.unsubscribe(()=>{}),c.unbindStore({}),c.hasSubscribers);
    out.push(c.runStores(5,function(a,b){return [this===receiver,a,b]},receiver,7,11));
    out.push(c.runStores(5,()=>marker)===marker);
    assert(!c.hasSubscribers,"inactive run");
  } else if (kind === "registry") {
    const s=Symbol("name"),t=Symbol("name"),a=channel("x"),b=channel(s);
    out.push(a===channel("x"),b===channel(s),b!==channel(t),a!==b,
      D.hasSubscribers("absent"),D.hasSubscribers(3),D.hasSubscribers({}));
    const replaced=new D.Channel("x");
    out.push(replaced!==a,channel("x")===replaced);
    const object={},raw=new D.Channel(object),number=new D.Channel(17),none=new D.Channel();
    out.push(channel(object)===raw,channel(17)===number,channel()===none);
  } else if (kind === "name-errors") {
    for (const value of [undefined,null,0,true,{},[],()=>{},1n]) {
      const e=reason(()=>channel(value));
      assert(e.code==="ERR_INVALID_ARG_TYPE","actual name code");
      out.push(e.code,e.message,e instanceof TypeError);
    }
    out.push(channel("")===channel(""),channel(Symbol.for("k"))===channel(Symbol.for("k")));
  } else if (kind === "instanceof") {
    const c=channel("instance"),p=D.Channel.prototype;
    out.push(c instanceof D.Channel,Object.create(p) instanceof D.Channel);
    class Child extends D.Channel {}
    const child=new Child("child");
    out.push(child instanceof Child,child instanceof D.Channel);
    c.subscribe(()=>{});
    const active=Object.getPrototypeOf(c),Active=active.constructor;
    out.push(c instanceof D.Channel,c instanceof Active,Object.create(active) instanceof D.Channel);
    out.push(Object.create(c) instanceof D.Channel);
    for(const v of [1,"x",true,Symbol("s"),1n,undefined,null]) {
      try { out.push(D.Channel[Symbol.hasInstance](v)); }
      catch(e) { out.push(e instanceof TypeError); }
    }
    out.push(functionView(Active),Object.keys(new Active()));
  } else if (kind === "transitions") {
    const c=channel("changes"),p=D.Channel.prototype,fn=()=>{};
    c.subscribe(fn);
    const active=Object.getPrototypeOf(c);
    out.push(active!==p,c.hasSubscribers,c instanceof D.Channel,c._stores.size,c._subscribers.length);
    out.push(c.unsubscribe(fn),Object.getPrototypeOf(c)===p,c.hasSubscribers,
      c._subscribers===undefined,c._stores===undefined);
    c.bindStore({run(_,next){return next()}});
    out.push(Object.getPrototypeOf(c)===active,c.hasSubscribers,c._subscribers.length,c._stores.size);
  } else if (kind === "duplicates") {
    const c=channel("duplicates"),events=[],fn=(d,n)=>events.push([d,n]);
    c.subscribe(fn);c.subscribe(fn);c.publish(2);
    out.push(c._subscribers.length,c.unsubscribe(fn),c._subscribers.length);
    c.publish(3);out.push(c.unsubscribe(fn),c.hasSubscribers,c.unsubscribe(fn),events);
  } else if (kind === "invalid-subscription") {
    const c=channel("bad"),p=D.Channel.prototype;
    for (const value of [null,undefined,17,{},Symbol("x")]) {
      const e=reason(()=>c.subscribe(value));
      assert(e.code==="ERR_INVALID_ARG_TYPE","subscription code");
      out.push(e.code,e.message,e instanceof TypeError);
    }
    out.push(Object.getPrototypeOf(c)!==p,c.hasSubscribers,c._subscribers.length,c._stores.size);
    out.push(c.unsubscribe(()=>{}),c.hasSubscribers);
  } else if (kind === "public-forward") {
    const c=channel("forward"),marker={},fn=()=>{};
    c.subscribe=function(v){out.push(this===c,v===fn);return marker};
    c.unsubscribe=function(v){out.push(this===c,v===fn);return 37};
    out.push(D.subscribe("forward",fn)===marker,D.unsubscribe("forward",fn));
    Object.defineProperty(c,"hasSubscribers",{get(){out.push("get");return marker}});
    out.push(D.hasSubscribers("forward")===marker);
  } else if (kind === "subscriber-call") {
    const c=channel("messages"),data={},events=[];
    c.subscribe(function(d,n){events.push(this===undefined,arguments.length,d===data,n)});
    c.subscribe(function(d,n){events.push(this===undefined,d===data,n)});
    out.push(c.publish(data),events);
  } else if (kind === "snapshot-remove") {
    const c=channel("remove"),events=[];
    const b=()=>events.push("b"),a=()=>{events.push("a");c.unsubscribe(b)};
    c.subscribe(a);c.subscribe(b);c.publish(1);c.publish(2);
    out.push(events,c._subscribers.length,c.hasSubscribers);
  } else if (kind === "snapshot-add") {
    const c=channel("add"),events=[];
    let once=false;
    c.subscribe(()=>{events.push("a");if(!once){once=true;c.subscribe(()=>events.push("b"))}});
    c.publish(1);c.publish(2);out.push(events,c._subscribers.length);
  } else if (kind === "live-length") {
    const c=channel("length");c.subscribe(()=>{});const active=Object.getPrototypeOf(c);
    const events=[];let reads=0;
    const list={0(){events.push("0")},1(){events.push("1")},get length(){
      events.push("length");return {valueOf(){events.push("coerce");return ++reads===1?2:0}}}};
    active.publish.call({_subscribers:list,name:"custom"},23);
    out.push(events);
  } else if (kind === "null-snapshot") {
    const c=channel("null");c.subscribe(()=>{});const publish=c.publish;
    for(const value of [undefined,null]) out.push(publish.call({_subscribers:value},1));
    out.push(dcReports().length);
  } else if (kind === "subscriber-error") {
    const c=channel("error"),events=[];
    c.subscribe(()=>{events.push("throw");throw dcError});
    c.subscribe(()=>events.push("continue"));c.publish(1);
    out.push(events,dcReports().length);
    const previous=dcFinish;dcFinish=()=>{const r=dcReports();assert(r.length===1&&r[0][0]===dcError,"original deferred reason");return previous()};
  } else if (kind === "name-getter-error") {
    const c=channel("name");c.subscribe(()=>out.push("unreachable"));
    Object.defineProperty(c,"name",{get(){throw dcError}});
    c.publish(1);out.push(dcReports().length);
    const previous=dcFinish;dcFinish=()=>{assert(dcReports()[0][0]===dcError,"name getter reason");return previous()};
  } else if (kind === "next-tick-callee") {
    const c=channel("tick"),events=[];c.subscribe(()=>{throw dcError});c.subscribe(()=>events.push("after"));
    Object.defineProperty(P,"nextTick",{configurable:true,get(){events.push("get");throw dcError}});
    out.push(reason(()=>c.publish(1))===dcError,events,dcReports().length);
  } else if (kind === "next-tick-reentry") {
    const c=channel("tick-reentry"),events=[],original=P.nextTick;
    let nested=false;c.subscribe(()=>{events.push(nested?"inner":"outer");if(!nested)throw dcError});
    P.nextTick=function(callback){events.push(this===P,arguments.length,callback.name,callback.length);
      nested=true;c.publish(2);nested=false;return Reflect.apply(original,this,[callback])};
    c.publish(1);out.push(events);
  } else if (kind === "stores-only") {
    const c=channel("stores"),s={run(v,next){out.push(v);return next()}};
    c.bindStore(s);out.push(c.hasSubscribers,c._subscribers.length,c._stores.size);
    out.push(c.runStores(7,()=>11));
    out.push(c.unbindStore(s),c.hasSubscribers,c._stores===undefined,c.unbindStore(s));
  } else if (kind === "store-replacement") {
    const c=channel("replace"),events=[],s={run(v,next){events.push(v);return next()}};
    c.bindStore(s,d=>d+1);c.bindStore(s,d=>d+2);out.push(c._stores.size,c.hasSubscribers);
    out.push(c.runStores(5,()=>13),events,c.unbindStore(s),c.hasSubscribers);
  } else if (kind === "store-order") {
    const c=channel("order"),events=[];let context="";
    const make=n=>({run(v,next){const old=context;context+=n+v;events.push("enter:"+n+":"+v);
      try{return next()}finally{events.push("leave:"+n);context=old}}});
    c.subscribe((d,n)=>events.push("publish:"+context+":"+d+":"+n));
    c.bindStore(make("a"),d=>{events.push("transform:a");return d+1});
    c.bindStore(make("b"),d=>{events.push("transform:b");return d+2});
    out.push(c.runStores(3,()=>{events.push("fn:"+context);return 17}),events,context);
  } else if (kind === "rest-call") {
    const c=channel("rest"),receiver={},data={};
    c.subscribe(()=>{});
    const iterable=Array.prototype[Symbol.iterator];
    Array.prototype[Symbol.iterator]=function(){throw Error("rest must not iterate")};
    try { out.push(c.runStores(data,function(a,b){return [this===receiver,arguments.length,a,b]},receiver,19,23)); }
    finally {Array.prototype[Symbol.iterator]=iterable}
  } else if (kind === "transform-error") {
    const c=channel("transform"),events=[];
    c.subscribe(()=>events.push("publish"));
    c.bindStore({run(v,next){events.push("inner:"+v);return next()}},d=>d+1);
    c.bindStore({run(){events.push("unreachable")}},()=>{events.push("throw");throw dcError});
    out.push(c.runStores(5,()=>{events.push("fn");return 29}),events,dcReports().length);
  } else if (kind === "noncallable-transform") {
    const c=channel("invalid-transform");c.bindStore({run(){out.push("unreachable")}},null);
    out.push(c.runStores(1,()=>31));const previous=dcFinish;
    dcFinish=()=>{const r=dcReports();assert(r.length===1&&r[0][0] instanceof TypeError,"transform TypeError");return previous()};
  } else if (kind === "store-error") {
    const c=channel("store-error");c.bindStore({run(){throw dcError}});
    out.push(reason(()=>c.runStores(1,()=>out.push("unreachable")))===dcError,dcReports().length);
  } else if (kind === "store-method-live") {
    const c=channel("live-store"),events=[],store={get run(){events.push("run:get");return function(v,next){
      events.push(this===store,v);return next()}}};
    c.bindStore(store,d=>{events.push("transform");return d*2});
    out.push(c.runStores(4,()=>37),events);
  } else if (kind === "entries-next-cache") {
    const c=channel("iterator"),events=[];c.subscribe(()=>{});
    let next=0;const store={run(v,fn){events.push(v);return fn()}};
    const iterator={next(){next++;events.push("next:"+next);
      this.next=()=>{throw Error("recached next")};
      return next===1?{done:false,value:[store,d=>d+3]}:{done:true}}};
    c._stores={entries(){events.push("entries");return {[Symbol.iterator](){events.push("iterator");return iterator}}}};
    out.push(c.runStores(5,()=>41),events);
  } else if (kind === "entries-indexed") {
    const c=channel("indexed"),events=[];c.subscribe(()=>{});
    const entry={get 0(){events.push("0");return {run(v,n){events.push(v);return n()}}},
      get 1(){events.push("1");return d=>d+4},[Symbol.iterator](){throw Error("entry must use indexed reads")}};
    c._stores={entries(){return [entry]}};
    out.push(c.runStores(6,()=>43),events);
  } else if (kind === "iterator-next-error") {
    const c=channel("next-error"),events=[];c.subscribe(()=>{});
    const iterator={
      next(){events.push("next");throw dcError},
      return(){events.push("return");return {}}
    };
    c._stores={entries(){return {[Symbol.iterator](){return iterator}}}};
    out.push(reason(()=>c.runStores(1,()=>0))===dcError,events);
  } else if (kind === "iterator-body-error") {
    const c=channel("body-error"),events=[];c.subscribe(()=>{});
    const iterator={
      next(){return {done:false,value:{get 0(){events.push("0");throw dcError}}}},
      return(){events.push("return");return 17}
    };
    c._stores={entries(){return {[Symbol.iterator](){return iterator}}}};
    out.push(reason(()=>c.runStores(1,()=>0))===dcError,events);
  } else if (kind === "iterator-close-error") {
    const c=channel("close-error"),events=[];c.subscribe(()=>{});
    const iterator={
      next(){return {done:false,value:{get 1(){throw dcError},0:{}}}},
      return(){events.push("return");throw {tag:"secondary"}}
    };
    c._stores={entries(){return {[Symbol.iterator](){return iterator}}}};
    out.push(reason(()=>c.runStores(1,()=>0))===dcError,events);
  } else if (kind === "generic-store-ops") {
    const c=channel("generic"),events=[];c.subscribe(()=>{});const ap=Object.getPrototypeOf(c);
    const stores={has(k){events.push("has",k);return false},set(k,t){events.push("set",k,t);return this},
      delete(k){events.push("delete",k);return false},get size(){events.push("size");return 0}};
    const receiver={_stores:stores,_subscribers:[],name:"generic"};
    ap.bindStore.call(receiver,"s","t");
    stores.has=function(k){events.push("has2",k);return true};
    out.push(ap.unbindStore.call(receiver,"s"),events,Object.getPrototypeOf(receiver)===D.Channel.prototype);
  } else if (kind === "primordial-poison") {
    const c=channel("poison"),events=[],fn=()=>events.push("called");
    const arraySaved=[Array.prototype.slice,Array.prototype.indexOf,Array.prototype.push];
    const objectSaved=[Object.getPrototypeOf,Object.setPrototypeOf];const poison=()=>{throw Error("late primordial")};
    Array.prototype.slice=Array.prototype.indexOf=Array.prototype.push=poison;
    Object.getPrototypeOf=Object.setPrototypeOf=poison;
    try { c.subscribe(fn);c.publish(1);out[0]=c.unsubscribe(fn);out[1]=c.hasSubscribers; }
    finally { [Array.prototype.slice,Array.prototype.indexOf,Array.prototype.push]=arraySaved;
      [Object.getPrototypeOf,Object.setPrototypeOf]=objectSaved; }
    // The subscriber deliberately invokes the poisoned public push and defers
    // that actual error; registry/prototype operations still use primordials.
    out.push(events.length);
  } else if (kind === "prototype-set-order") {
    const events=[],target={};
    const p=new Proxy(target,{setPrototypeOf(t,v){events.push("prototype");return Reflect.setPrototypeOf(t,v)},
      set(t,k,v,r){events.push(k);return Reflect.set(t,k,v,r)}});
    D.Channel.prototype.subscribe.call(p,()=>{});
    out.push(events,Object.getPrototypeOf(target)!==D.Channel.prototype,target.hasSubscribers,target._subscribers.length);
  } else if (kind === "message-lifetime") {
    const c=channel("message-life"),events=[];c.subscribe(()=>{});
    let n=0;c._subscribers={get length(){events.push("length:"+dcRetired());return n++<2?2:0},
      get 0(){events.push("get0:"+dcRetired());return dcMessageProbe()},
      get 1(){events.push("get1:"+dcRetired());return ()=>events.push("second")}};
    c.publish(1);out.push(events,dcRetired());
  } else if (kind === "entry-lifetime") {
    const c=channel("entry-life"),events=[];c.subscribe(()=>{});
    const store={run(v,n){events.push("run:"+dcRetired());return n()}};
    let n=0;c._stores={entries(){return {[Symbol.iterator](){return {
      next(){return n++===0?{done:false,value:dcEntryProbe(store,d=>{events.push("transform:"+dcRetired());return d})}:{done:true}}
    }}}}};
    out.push(c.runStores(1,()=>{events.push("fn:"+dcRetired());return 47}),events,dcRetired());
  } else if (kind === "catch-lifetime") {
    const c=channel("catch-life"),events=[];c.subscribe(()=>{throw dcEntryProbe({},undefined)});
    c.subscribe(()=>events.push("second:"+dcRetired()));
    // The observer binding retains the reason, then dcDropReports releases it.
    P.nextTick=function(callback){events.push("schedule:"+dcRetired());callback();dcDropReports()};
    c.publish(1);out.push(events,dcRetired());
  } else if (kind === "store-get-lifetime") {
    const c=channel("store-get-life"),events=[];c.subscribe(()=>{});
    c._stores={entries(){return {[Symbol.iterator](){return {
      next(){return {done:false,value:{get 0(){return dcEntryProbe()},get 1(){throw dcError}}}},
      return(){events.push("close:"+dcRetired());return {done:true}}
    }}}}};
    out.push(reason(()=>c.runStores(1,()=>0))===dcError,events,dcRetired());
  } else if (kind === "slice-argument-lifetime") {
    const c=channel("slice-life"),events=[];c.subscribe(()=>{});const ap=Object.getPrototypeOf(c);
    let current,assigned=false;
    const receiver={name:"slice-life",get _subscribers(){
      if(assigned)return current;
      const value=dcEntryProbe();Object.defineProperty(value,"length",{value:0});return value;
    },set _subscribers(value){events.push("set:"+dcRetired());current=value;assigned=true}};
    ap.subscribe.call(receiver,()=>{});
    out.push(events,dcRetired(),current.length);
  } else if (kind === "pending-reason") {
    const c=channel("pending");c.subscribe(()=>dcPending());c.subscribe(()=>out.push("continued"));
    c.publish(1);const previous=dcFinish;
    dcFinish=()=>{assert(dcReports()[0][0]===dcError,"actual pending reason");return previous()};
  } else {
    throw Error("unknown diagnostics control " + kind);
  }
};

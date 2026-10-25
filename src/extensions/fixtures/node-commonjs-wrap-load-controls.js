"use strict";
function wrapLoadMeasure(factory, scenario) {
  const events = [], outcomes = [];
  const reasons = { load:{kind:"load"}, end:{kind:"end"}, start:{kind:"start"}, getter:{kind:"getter"}, channel:{kind:"channel"} };
  const returned = {returned:true};
  let fn, update, initializations=0, channelCalls=0, coercions=0, loads=0;
  const text = x => x === undefined ? "$undefined" : x === null ? "$null" : typeof x === "object" ? x === parent ? "$parent" : x === request ? "$request" : "$object" : x;
  function caught(e) { for (const [name, value] of Object.entries(reasons)) if (e===value) return name; return e && e.name || typeof e; }
  let request = "alpha", parent = {id:"parent",filename:"parent.cjs"};
  const options = {token:true};
  function start(label, trace) {
    events.push(["start",label,trace]);
    if (scenario===5) throw reasons.start;
    if (scenario===13) update(start, function(l,t){events.push(["updated-end",l,t])});
  }
  function end(label, trace) {
    events.push(["end",label,trace]);
    if (scenario===9 || scenario===10) throw reasons.end;
  }
  function timerFactory(label, callback) {
    events.push(["timerFactory",label]); update=callback;
    if (scenario===20) callback(start,end);
    if (scenario===23) return {startTimer:17,endTimer:end};
    if (scenario===21) return {get startTimer(){events.push(["get-start"]);return start},get endTimer(){events.push(["get-end"]);callback(start,end);return end}};
    return {get startTimer(){events.push(["get-start"]);return start},get endTimer(){events.push(["get-end"]);return end}};
  }
  function loader(req, par, main, opts) {
    loads++;events.push(["load",this===actualWrapModule,arguments.length,text(req),text(par),text(main),opts===options]);
    if (scenario===8||scenario===10) throw reasons.load;
    if (scenario===14) update(start,function(l,t){events.push(["load-updated-end",l,t])});
    if (scenario===28 && req==="outer") fn("inner",par,false,opts);
    return scenario===19 ? 7 : returned;
  }
  Object.defineProperty(actualWrapModule,"_load",{configurable:true,get(){
    events.push(["get-load"]);if(scenario===7)throw reasons.getter;return loader;
  }});
  const traceSync = function(f, context, self, ...args) {
    events.push(["trace",this===traceChannel,context.parentFilename,text(context.id),Object.getPrototypeOf(context)===null,Object.keys(context).join(","),Object.values(Object.getOwnPropertyDescriptors(context)).every(d=>d.writable&&d.enumerable&&d.configurable)]);
    if (scenario===12) throw reasons.load;
    return Reflect.apply(f,self,args);
  };
  const traceChannel = {
    get hasSubscribers(){events.push(["subscribers"]);if(scenario===6)throw reasons.getter;return scenario===22 ? loads===0 : [2,11,12,18,24].includes(scenario) ? true : scenario===29 ? {truthy:true} : false},
    get traceSync(){events.push(["get-trace"]);if(scenario===11)throw reasons.getter;return traceSync},
  };
  function tracingChannel(name) {
    channelCalls++;events.push(["channel",name,channelCalls]);
    if(scenario===15&&channelCalls===1)throw reasons.channel;
    if(scenario===16&&channelCalls===1){fn("inner",parent,false,options);return {get hasSubscribers(){events.push(["outer-subscribers"]);return false}}}
    if(scenario===17)return undefined;
    return traceChannel;
  }
  if(scenario===3) {
    parent={get id(){events.push(["parent-id"]);return {[Symbol.toPrimitive](hint){events.push(["parent-coerce",hint]);return "P"}}},filename:"parent.cjs"};
    request={[Symbol.toPrimitive](hint){events.push(["request-coerce",hint,++coercions]);return "R"+coercions}};
  }
  if(scenario===4)parent=null;
  if(scenario===25) {
    parent={id:0,get filename(){throw Error("untraced filename was read")}};
    Object.defineProperty(traceChannel,"traceSync",{get(){throw Error("untraced trace was read")}});
  }
  if(scenario===2||scenario===24) {
    Object.defineProperty(parent,"filename",{get(){events.push(["filename"]);if(scenario===24)throw reasons.getter;Object.defineProperty(actualWrapModule,"_load",{value(){throw Error("late loader used")},configurable:true,writable:true});return "observed.cjs"}});
  }
  if(scenario===27)request=Symbol("request");
  if(scenario===28)request="outer";
  if(scenario===30)parent=undefined;
  if(scenario===31)request={toString(){events.push(["coercion-throw"]);throw reasons.getter}};
  try {
    fn=factory(timerFactory,tracingChannel);initializations++;
    if(scenario===0)events.push(["metadata",fn.name,fn.length,Object.hasOwn(fn,"prototype")]);
    if(scenario===26)actualWrapModule.Module={_load(){throw Error("mutable Module.Module used")}};
    const count=[13,15,16,17,22].includes(scenario)?2:1;
    for(let i=0;i<count;i++){
      try {
        const result=scenario===19?new fn(request,parent,true,options):fn(request,parent,true,options);
        outcomes.push(scenario===19?["instance",result instanceof fn]:["return",result===returned]);
      } catch(e){outcomes.push(["throw",caught(e)])}
    }
  } catch(e){outcomes.push(["factory-throw",caught(e)])}
  delete actualWrapModule.Module;
  return {events,outcomes,initializations,channelCalls,loads};
}
globalThis.runWrapLoadCase = function(scenario) {
  const baseline = wrapLoadMeasure(makeOriginalModuleLoad,scenario);
  const actual = wrapLoadMeasure(makeNativeModuleLoad,scenario);
  if (JSON.stringify(baseline)!==JSON.stringify(actual)) throw Error(JSON.stringify({scenario,baseline,actual}));
  if(scenario===1 && (actual.loads!==1 || actual.outcomes[0][0]!=="return"))throw Error("direct path vacuous");
  if(scenario===2 && !actual.events.some(e=>e[0]==="trace"))throw Error("traced path vacuous");
  if(scenario===5 && actual.events.some(e=>e[0]==="end"))throw Error("start lies outside finally");
  if(scenario===10 && actual.outcomes[0][1]!=="end")throw Error("finally did not replace throw");
  if(scenario===13 && !actual.events.some(e=>e[0]==="updated-end"))throw Error("live timer not observed");
  if(scenario===15 && (actual.channelCalls!==2 || actual.loads!==1))throw Error("lazy retry did not execute");
  if(scenario===17 && actual.channelCalls!==1)throw Error("undefined cache not retained");
  if(scenario===20 && actual.outcomes[0][1]!=="ReferenceError")throw Error("initializer TDZ absent");
  if(scenario===22 && (actual.loads!==2 || actual.events.filter(e=>e[0]==="trace").length!==1 || actual.events.filter(e=>e[0]==="subscribers").length!==2))throw Error("subscriber path transition absent");
  return true;
};

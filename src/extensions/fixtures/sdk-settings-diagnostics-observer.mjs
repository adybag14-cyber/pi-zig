// Controls execute the complete original bodies and native owner in fresh VMs.
// Every collect caller uses the actual native SettingsManager and its backing
// error array. Descriptor mutations are observational inputs to those methods.
function expectDiagnostic(value, message) {
  if (!value) throw new Error("settings diagnostics control: " + message);
}
function equalDiagnostic(a, b, message) {
  expectDiagnostic(JSON.stringify(a) === JSON.stringify(b), message);
}
function seedDiagnostics(s, rows) { s.data.errors = rows; }
function collectDiagnostics(s) { return s.owner.collectSettingsDiagnostics(s.manager); }
function rowDiagnostic(scope, path, message) { return {scope, path, error:{message}}; }
function observeDiagnosticShapes(s) {
  const rows = [];
  for (const name of ["collectSettingsDiagnostics","deduplicateDiagnostics"]) {
    const f=s.owner[name], d=Object.getOwnPropertyDescriptor(f,"prototype");
    expectDiagnostic(typeof f==="function" && f.name===name && f.length===1,"complete original ordinary function shape");
    rows.push([name,f.length,Reflect.ownKeys(f),d.writable,d.enumerable,d.configurable,f.prototype.constructor===f]);
  }
  return rows;
}
function observeDiagnosticDrain(s) {
  const original=[rowDiagnostic("global","/agent/settings.json","invalid JSON"),rowDiagnostic("project",undefined,"storage unavailable")];
  seedDiagnostics(s,original);
  const first=collectDiagnostics(s), second=collectDiagnostics(s);
  equalDiagnostic(first,[{type:"warning",message:"Invalid settings file /agent/settings.json: invalid JSON"},{type:"warning",message:"Invalid project settings: storage unavailable"}],"exact original messages");
  equalDiagnostic(second,[],"real manager drained errors");
  expectDiagnostic(s.data.errors!==original && s.data.errors.length===0,"fresh real backing array");
  return [first,second,original.length];
}
function observeDiagnosticStorage(s) {
  const calls=[],reason=new Error("storage unavailable");
  const storage={withLock(scope,fn){calls.push(scope);if(scope==="global")throw reason;return fn(undefined);}};
  const manager=s.SettingsManager.fromStorage(storage);
  const result=s.owner.collectSettingsDiagnostics(manager);
  equalDiagnostic(result,[{type:"warning",message:"Invalid global settings: storage unavailable"}],"actual storage load error without a path");
  equalDiagnostic(s.owner.collectSettingsDiagnostics(manager),[],"actual storage error drained once");
  return [calls,result];
}
function observeDiagnosticPaths(s) {
  const paths=[undefined,null,false,0,-0,NaN,"",true,7,"p"];
  seedDiagnostics(s,paths.map(path=>rowDiagnostic("global",path,"x")));
  const result=collectDiagnostics(s);
  expectDiagnostic(result.slice(0,7).every(x=>x.message==="Invalid global settings: x"),"truthy path rule");
  equalDiagnostic(result.slice(7).map(x=>x.message),["Invalid settings file true: x","Invalid settings file 7: x","Invalid settings file p: x"],"path template conversion");
  return result;
}
function observeDiagnosticLiveMap(s) {
  const order=[],rows=[];
  Object.defineProperty(rows,"map",{get(){order.push("map:Get");return function(cb){
    order.push("map:Call");expectDiagnostic(this===rows && arguments.length===1,"map receiver and one callback");
    expectDiagnostic(cb.length===1 && cb.name==="" && !Object.hasOwn(cb,"prototype"),"original anonymous arrow");
    let construct=false;try{new cb({});}catch(e){construct=e instanceof TypeError;}
    expectDiagnostic(construct,"row callback is not constructible");
    return {custom:true,value:cb(rowDiagnostic("project",null,"x"),17,rows)};
  };}});
  seedDiagnostics(s,rows);const out=collectDiagnostics(s);
  equalDiagnostic(order,["map:Get","map:Call"],"map live lookup");
  return [order,out];
}
function observeDiagnosticSparseMap(s) {
  const rows=[];rows.length=4;rows[2]=rowDiagnostic("global",null,"hole");
  seedDiagnostics(s,rows);const out=collectDiagnostics(s);
  expectDiagnostic(out.length===4 && !(0 in out) && (2 in out) && !(3 in out),"actual map retains holes");
  return [out.length,Object.keys(out),out[2]];
}
function observeDiagnosticDestructure(s) {
  const order=[],row={};
  for(const name of ["scope","path","error"])
    Object.defineProperty(row,name,{get(){order.push(name);return name==="error"?{get message(){order.push("message");return "x";}}:name==="path"?"p":"global";}});
  seedDiagnostics(s,[row]);const out=collectDiagnostics(s);
  equalDiagnostic(order,["scope","path","error","message"],"all destructuring Gets precede literal");
  return [order,out];
}
function observeDiagnosticPrimitiveBox(s) {
  const old=Object.getOwnPropertyDescriptors(Number.prototype),order=[];
  let first;
  try {
    Object.defineProperties(Number.prototype,{
      scope:{configurable:true,get(){order.push(["scope",typeof this]);first=this;this.tag=1;return "global";}},
      path:{configurable:true,get(){order.push(["path",this===first,this.tag]);return null;}},
      error:{configurable:true,get(){order.push(["error",this===first,this.tag]);return {message:"boxed"};}},
    });
    seedDiagnostics(s,[17]);const out=collectDiagnostics(s);
    equalDiagnostic(order,[["scope","object"],["path",true,1],["error",true,1]],"one original ToObject receiver");
    return [order,out];
  } finally {
    for(const k of ["scope","path","error"]) {if(old[k])Object.defineProperty(Number.prototype,k,old[k]);else delete Number.prototype[k];}
  }
}
function observeDiagnosticMessageOrder(s) {
  const order=[],path={toString(){order.push("path:string");return "where";}};
  const error={get message(){order.push("message:Get");return {toString(){order.push("message:string");return "why";}};}};
  seedDiagnostics(s,[{get scope(){order.push("scope:Get");return "global";},get path(){order.push("path:Get");return path;},get error(){order.push("error:Get");return error;}}]);
  const out=collectDiagnostics(s);
  equalDiagnostic(order,["scope:Get","path:Get","error:Get","path:string","message:Get","message:string"],"template order");
  return [order,out];
}
function observeDiagnosticNullishRow(s) {
  const out=[];
  for(const row of [undefined,null]) {
    seedDiagnostics(s,[row]);let caught;
    try{collectDiagnostics(s);}catch(e){caught=e;}
    expectDiagnostic(caught instanceof TypeError,"nullish destructuring rejects");
    out.push([caught.name,s.data.errors.length]);
  }
  return out;
}
function observeDiagnosticSymbols(s) {
  const out=[];
  for(const row of [rowDiagnostic("global",Symbol("p"),"x"),rowDiagnostic(Symbol("scope"),null,"x"),rowDiagnostic("global","p",Symbol("message"))]) {
    seedDiagnostics(s,[row]);let caught;try{collectDiagnostics(s);}catch(e){caught=e;}
    expectDiagnostic(caught instanceof TypeError,"template symbol throws");
    out.push(caught.name);
  }
  return out;
}
function observeDiagnosticDestructureFailure(s) {
  const order=[],sentinel={same:true};
  seedDiagnostics(s,[{get scope(){order.push("scope");return "global";},get path(){order.push("path");throw sentinel;},get error(){order.push("error");return {};}}]);
  let caught;try{collectDiagnostics(s);}catch(e){caught=e;}
  expectDiagnostic(caught===sentinel,"original Get throw identity");
  equalDiagnostic(order,["scope","path"],"later destructuring Get suppressed");
  return [order,caught===sentinel,s.data.errors.length];
}
function observeDiagnosticMapEscape(s) {
  let escaped;
  const rows=[];rows.map=function(cb){escaped=cb;return "custom";};
  seedDiagnostics(s,rows);
  expectDiagnostic(collectDiagnostics(s)==="custom","direct map return retained");
  const out=escaped(rowDiagnostic("project",null,"later"));
  expectDiagnostic(out.message==="Invalid project settings: later","escaped row arrow survives outer return");
  return out;
}
function observeDiagnosticMapFailure(s) {
  const rows=[],sentinel={same:true},order=[];
  Object.defineProperty(rows,"map",{get(){order.push("map");throw sentinel;}});
  seedDiagnostics(s,rows);let caught;try{collectDiagnostics(s);}catch(e){caught=e;}
  expectDiagnostic(caught===sentinel && s.data.errors.length===0,"drain precedes map failure");
  return [order,caught===sentinel];
}
function observeDiagnosticFirstOccurrence(s) {
  const a={type:"warning",message:"x",extra:1},b={type:"warning",message:"x",extra:2},c={type:"error",message:"x"},d={type:"warning",message:"y"};
  const out=s.owner.deduplicateDiagnostics([a,b,c,d,a]);
  expectDiagnostic(out.length===3 && out[0]===a && out[1]===c && out[2]===d,"first exact type/message identity and order");
  return out;
}
function observeDiagnosticNulCollision(s) {
  const a={type:"a\0b",message:"c"},b={type:"a",message:"b\0c"};
  const out=s.owner.deduplicateDiagnostics([a,b]);
  expectDiagnostic(out.length===1 && out[0]===a,"preserve original NUL concatenation collision");
  return out;
}
function observeDiagnosticSparseFilter(s) {
  const rows=[];rows.length=5;rows[1]={type:"warning",message:"a"};rows[4]={type:"warning",message:"a"};
  const out=s.owner.deduplicateDiagnostics(rows);
  expectDiagnostic(out.length===1 && out[0]===rows[1],"filter skips holes and retains first");
  const generic={0:rows[1],2:{type:"warning",message:"b"},length:3,filter:Array.prototype.filter};
  const other=s.owner.deduplicateDiagnostics(generic);
  expectDiagnostic(other.length===2 && other[1]===generic[2],"actual generic filter");
  return [out,other];
}
function observeDiagnosticSetOrder(s) {
  const NativeSet=globalThis.Set,order=[],input={get filter(){order.push("filter:Get");return function(cb){
    order.push("filter:Call");expectDiagnostic(this===input && arguments.length===1,"filter receiver and argument count");
    expectDiagnostic(cb.name==="" && cb.length===1 && !Object.hasOwn(cb,"prototype"),"filter is original arrow");
    return "live";
  };}};
  Object.defineProperty(globalThis,"Set",{configurable:true,get(){order.push("Set:Get");return function(){
    order.push(["Set:construct",new.target!==undefined,arguments.length]);return new NativeSet();
  };}});
  try {expectDiagnostic(s.owner.deduplicateDiagnostics(input)==="live","filter return passed through");return order;}
  finally{Object.defineProperty(globalThis,"Set",{value:NativeSet,writable:true,configurable:true});}
}
function observeDiagnosticSetFailure(s) {
  const old=globalThis.Set,sentinel={same:true},order=[];
  globalThis.Set=function(){order.push("Set");throw sentinel;};
  try {
    let caught;try{s.owner.deduplicateDiagnostics({get filter(){order.push("filter");throw Error("later");}});}catch(e){caught=e;}
    expectDiagnostic(caught===sentinel,"Set constructor error identity");
    equalDiagnostic(order,["Set"],"constructor before filter lookup");
    return [order,caught===sentinel];
  } finally {globalThis.Set=old;}
}
function observeDiagnosticHasAdd(s) {
  const old=globalThis.Set,order=[],keys=[],seen={};
  Object.defineProperties(seen,{
    has:{get(){order.push("has:Get");return function(key){order.push(["has",this===seen,arguments.length,key]);return keys.includes(key);};}},
    add:{get(){order.push("add:Get");return function(key){order.push(["add",this===seen,arguments.length,key]);keys.push(key);return {ignored:true};};}},
  });
  globalThis.Set=function(){return seen;};
  try {
    const out=s.owner.deduplicateDiagnostics([{type:"warning",message:"x"},{type:"warning",message:"x"}]);
    expectDiagnostic(out.length===1 && keys.length===1,"live has/add semantics");
    return [order,out];
  } finally {globalThis.Set=old;}
}
function observeDiagnosticTruthyHasRetirement(s,hooks) {
  const old=globalThis.Set,order=[];
  globalThis.Set=function(){return {has(){order.push(["has",hooks.count(0)]);return hooks.make(0);},get add(){throw Error("truthy has suppresses add");}};};
  try {
    const input={filter(cb){const decision=cb({type:"x",message:"y"});order.push(["after",decision,hooks.count(0)]);return decision;}};
    const out=s.owner.deduplicateDiagnostics(input);
    expectDiagnostic(out===false && hooks.count(0)===1,"truthy native holder retires");
    return order;
  } finally {globalThis.Set=old;}
}
function observeDiagnosticAddRetirement(s,hooks) {
  const old=globalThis.Set,order=[];
  globalThis.Set=function(){return {has(){return false;},add(){order.push("add");return hooks.make(0);}};};
  try {
    const input={filter(cb){const result=cb({type:"x",message:"y"});order.push([result,hooks.count(0)]);return result;}};
    expectDiagnostic(s.owner.deduplicateDiagnostics(input)===true,"new diagnostic accepted");
    expectDiagnostic(hooks.count(0)===1,"add ignored result retires before returning");
    return order;
  } finally {globalThis.Set=old;}
}
function observeDiagnosticKeyOrder(s) {
  const order=[],row={get type(){order.push("type:Get");return {toString(){order.push("type:string");return "w";}};},get message(){order.push("message:Get");return {toString(){order.push("message:string");return "x";}};}};
  const out=s.owner.deduplicateDiagnostics([row]);
  equalDiagnostic(order,["type:Get","type:string","message:Get","message:string"],"key template order");
  expectDiagnostic(out[0]===row,"original object returned");
  return order;
}
function observeDiagnosticKeyFailure(s) {
  const sentinel={same:true},order=[];
  const row={get type(){order.push("type");return {toString(){order.push("string");throw sentinel;}};},get message(){order.push("message");return "x";}};
  let caught;try{s.owner.deduplicateDiagnostics([row]);}catch(e){caught=e;}
  expectDiagnostic(caught===sentinel,"type conversion throw preserved");
  equalDiagnostic(order,["type","string"],"message suppressed after throw");
  return [order,caught===sentinel];
}
function observeDiagnosticEscape(s) {
  let first,second;
  s.owner.deduplicateDiagnostics({filter(cb){first=cb;return undefined;}});
  s.owner.deduplicateDiagnostics({filter(cb){second=cb;return undefined;}});
  const row={type:"warning",message:"x"},out=[first(row),first(row),second(row),first({type:"warning",message:"y"})];
  equalDiagnostic(out,[true,false,true,true],"per-invocation escaped lexical Set");
  return out;
}
function observeDiagnosticEscapeAfterThrow(s) {
  let escaped;const sentinel={same:true};
  let caught;try{s.owner.deduplicateDiagnostics({filter(cb){escaped=cb;throw sentinel;}});}catch(e){caught=e;}
  expectDiagnostic(caught===sentinel,"filter throw retained");
  const row={type:"warning",message:"later"},out=[escaped(row),escaped(row)];
  equalDiagnostic(out,[true,false],"actual lexical Set survives throwing filter");
  return [caught===sentinel,out];
}
function observeDiagnosticSetLifetime(s,hooks) {
  const old=globalThis.Set,order=[];let escaped;
  globalThis.Set=function(){const seen=hooks.make(0);seen.has=function(){return false;};seen.add=function(){};return seen;};
  try {
    s.owner.deduplicateDiagnostics({filter(cb){escaped=cb;order.push(hooks.count(0));return undefined;}});
    order.push(hooks.count(0));escaped({type:"w",message:"x"});order.push(hooks.count(0));
    escaped=null;order.push(hooks.count(0));
    equalDiagnostic(order,[0,0,0,1],"closed-over seen owned exactly through escaped arrow");
    return order;
  } finally {globalThis.Set=old;}
}
function observeDiagnosticPrivateData(s,hooks) {
  let privateReason;
  seedDiagnostics(s,[{get scope(){privateReason=hooks.freshPrivateData();throw privateReason;},path:null,error:{message:"unreached"}}]);
  let caught;try{collectDiagnostics(s);}catch(e){caught=e;}
  expectDiagnostic(caught===privateReason && hooks.isUnmarkedPrivateData(caught),"native private Error thrown as ordinary data");
  return [caught===privateReason,hooks.isUnmarkedPrivateData(caught)];
}
function observeDiagnosticRowLifetime(s,hooks) {
  const order=[],row={get scope(){const value=hooks.make(0);value.toString=function(){order.push(["scope:string",hooks.count(0),hooks.count(1)]);return "global";};return value;},
    get path(){return null;},get error(){const value=hooks.make(1);Object.defineProperty(value,"message",{get(){order.push(["message",hooks.count(0),hooks.count(1)]);return "x";}});return value;}};
  seedDiagnostics(s,[row]);const out=collectDiagnostics(s);
  order.push(["after",hooks.count(0),hooks.count(1)]);
  expectDiagnostic(hooks.count(0)===1 && hooks.count(1)===1,"destructured locals retire after callback");
  return [order,out];
}
function observeDiagnosticConstructorReturn(s) {
  const rows=[];rows.map=()=>17;seedDiagnostics(s,rows);
  const C=s.owner.collectSettingsDiagnostics,collect=new C(s.manager);
  expectDiagnostic(Object.getPrototypeOf(collect)===C.prototype,"ordinary collect constructor primitive return");
  const D=s.owner.deduplicateDiagnostics,dedupe=new D({filter(){return 19;}});
  expectDiagnostic(Object.getPrototypeOf(dedupe)===D.prototype,"ordinary dedupe constructor primitive return");
  return [Object.keys(collect),Object.keys(dedupe)];
}
function observeDiagnosticCurrentFatal(s,hooks) {
  const prior=hooks.freshPrivateData();expectDiagnostic(hooks.isUnmarkedPrivateData(prior),"successful data before current fatal");
  seedDiagnostics(s,[{get scope(){return hooks.raiseNativeFatal();},get path(){hooks.visit(1);},get error(){hooks.visit(2);}}]);
  try{collectDiagnostics(s);}catch(e){hooks.visit(3);}
  hooks.visit(1);
}
function observeDiagnosticHasRetirementFatal(s,hooks) {
  globalThis.Set=function(){return {has(){hooks.armFatal(0);return hooks.make(0);},get add(){hooks.visit(1);return function(){};}};};
  try{s.owner.deduplicateDiagnostics({filter(cb){const result=cb({type:"x",message:"y"});hooks.visit(2);return result;}});}catch(e){hooks.visit(3);}
  hooks.visit(1);
}
function observeDiagnosticHasRetirementCancel(s,hooks) {
  globalThis.Set=function(){return {has(){hooks.armCancel(0);return hooks.make(0);},get add(){hooks.visit(1);return function(){};}};};
  try{s.owner.deduplicateDiagnostics({filter(cb){const result=cb({type:"x",message:"y"});hooks.visit(2);return result;}});}catch(e){hooks.visit(3);}
  hooks.visit(1);
}

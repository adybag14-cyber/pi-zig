"use strict";
function expectSettings(value, message) { if (!value) throw new Error(message); }
function sameSettings(actual, expected, message) {
  expectSettings(JSON.stringify(actual) === JSON.stringify(expected), message + ": " + JSON.stringify(actual));
}
const simpleSettingsRows = [
 ["getSteeringMode",["steeringMode"]], ["getFollowUpMode",["followUpMode"]],
 ["getTransport",["transport"]], ["getCompactionEnabled",["compaction","enabled"]],
 ["getBranchSummarySkipPrompt",["branchSummary","skipPrompt"]], ["getRetryEnabled",["retry","enabled"]],
 ["getHideThinkingBlock",["hideThinkingBlock"]], ["getShowCacheMissNotices",["showCacheMissNotices"]],
 ["getCollapseChangelog",["collapseChangelog"]], ["getEnableInstallTelemetry",["enableInstallTelemetry"]],
 ["getEnableAnalytics",["enableAnalytics"]], ["getEnableSkillCommands",["enableSkillCommands"]],
 ["getShowImages",["terminal","showImages"]], ["getShowTerminalProgress",["terminal","showTerminalProgress"]],
 ["getFullscreenCopyOnSelect",["fullscreenCopyOnSelect"]], ["getImageAutoResize",["images","autoResize"]],
 ["getBlockImages",["images","blockImages"]], ["getDoubleEscapeAction",["doubleEscapeAction"]],
 ["getEditorPaddingX",["editorPaddingX"]], ["getAutocompleteMaxVisible",["autocompleteMaxVisible"]],
 ["getCodeBlockIndent",["markdown","codeBlockIndent"]]
];
function settingsParent(root, path) {
  let value = root;
  for (const name of path.slice(0,-1)) value = value[name] ??= {};
  return value;
}
function settingsWrite(root,path,value) { settingsParent(root,path)[path.at(-1)] = value; }
function settingsGet(root,path,get) {
  Object.defineProperty(settingsParent(root,path),path.at(-1),{get,configurable:true});
}
function resetSettings(subject) { subject.data.settings={};subject.data.global={}; }
function observeSettingsShapes(s) {
  const arities={getCompactionTokenSetting:2,getCompactionReserveTokens:1,getCompactionKeepRecentTokens:1,getCompactionSettings:1};
  const names=s.names;
  expectSettings(names.length===41,"complete selected getter set");
  for(const name of names) {
    const fn=s.manager[name];
    expectSettings(typeof fn==="function" && fn.name===name && fn.length===(arities[name]??0),"method metadata "+name);
    expectSettings(!Object.hasOwn(fn,"prototype"),"genuine nonconstructible method "+name);
    let threw=false;try{Reflect.construct(fn,[]);}catch(e){threw=e instanceof TypeError;}
    expectSettings(threw,"nonconstructible "+name);
  }
  expectSettings(s.manager instanceof s.SettingsManager && s.second instanceof s.SettingsManager,"actual manager constructor");
  expectSettings(typeof s.manager.setSessionShareDestination==="function","original missing setter installed");
  return names;
}
function observeSettingsDefinedSuppression(s) {
  const seen=[];
  for(const [method,path] of simpleSettingsRows) {
    resetSettings(s);
    const marker={method};
    settingsWrite(s.data.settings,path,marker);
    settingsGet(s.defaults,path,()=>{seen.push(method);throw new Error("eager default");});
    expectSettings(s.manager[method]()===marker,"defined value identity "+method);
  }
  sameSettings(seen,[],"no unnecessary fallback Get");
  return true;
}
function observeSettingsLiveFallbacks(s) {
  const seen=[];
  for(const [method,path] of simpleSettingsRows) {
    resetSettings(s);
    let current={method,version:1};
    settingsWrite(s.data.settings,path,null);
    settingsGet(s.defaults,path,()=>{seen.push(method);return current;});
    expectSettings(s.manager[method]()===current,"null live fallback "+method);
    current={method,version:2};
    settingsWrite(s.data.settings,path,undefined);
    expectSettings(s.manager[method]()===current,"undefined live fallback "+method);
  }
  expectSettings(seen.length===42,"one actual fallback per invocation");
  return seen;
}
function observeSettingsNullishAndTruthy(s) {
  const values=[false,0,"",NaN,null,undefined];
  for(const [method,path] of simpleSettingsRows) {
    resetSettings(s);const marker={method};settingsWrite(s.defaults,path,marker);
    for(const value of values){
      settingsWrite(s.data.settings,path,value);
      const truthy=method==="getSteeringMode"||method==="getFollowUpMode";
      const expected=truthy?!value:value==null;
      const actual=s.manager[method]();
      expectSettings(expected?actual===marker:Object.is(actual,value),"nullish versus truthy "+method);
    }
  }
  return true;
}
function observeSettingsSharedIdentity(s) {
  const first={phase:1},second={phase:2};s.defaults.transport=first;
  expectSettings(s.manager.getTransport()===first&&s.second.getTransport()===first,"shared first value");
  s.defaults.transport=second;
  expectSettings(s.manager.getTransport()===second&&s.second.getTransport()===second,"shared replacement");
  s.data.accessorDefaults={transport:"foreign old per-instance asset"};
  expectSettings(s.manager.getTransport()===second,"old accessorDefaults cannot shadow actual shared import");
  return true;
}
function observeSettingsGlobalTrust(s) {
  const order=[];const selected={selected:true};
  s.data.settings={defaultProjectTrust:"always"};
  Object.defineProperty(s.data.global,"defaultProjectTrust",{configurable:true,get(){order.push("global");return "ask";}});
  settingsGet(s.defaults,["defaultProjectTrust"],()=>{order.push("default");return selected;});
  expectSettings(s.manager.getDefaultProjectTrust()===selected,"ask must select live fallback");
  for(const policy of ["always","never"]){
    Object.defineProperty(s.data.global,"defaultProjectTrust",{configurable:true,value:policy,writable:true});
    expectSettings(s.manager.getDefaultProjectTrust()===policy,"global accepted policy");
  }
  sameSettings(order,["global","default"],"trust global and conditional order");
  return order;
}
function observeSettingsShare(s) {
  const selected={auto:"live"};s.defaults.sessionShareDestination=selected;
  for(const value of ["auto","other",null,undefined,0]){
    s.data.settings.sessionShareDestination=value;
    expectSettings(s.manager.getSessionShareDestination()===selected,"share invalid/live fallback");
  }
  settingsGet(s.defaults,["sessionShareDestination"],()=>{throw new Error("accepted share read fallback");});
  for(const value of ["gist","radius"]){s.data.settings.sessionShareDestination=value;expectSettings(s.manager.getSessionShareDestination()===value,"accepted destination");}
  return true;
}
function observeSettingsStrictChoices(s) {
  const rows=[
   ["getQuietStartup",["quietStartup"],[true,"header"],[false,"quiet","other"]],
   ["getTuiMode",["tuiMode"],["regular"],["fullscreen","other"]],
   ["getFullscreenExitOutput",["fullscreenExitOutput"],["resume-hint"],["transcript","other"]],
   ["getFullscreenScrollbar",["fullscreenScrollbar"],["always","hidden"],["auto","other"]],
   ["getMermaidRenderingMode",["markdown","mermaid"],["off","final"],["streaming","other"]],
  ];
  for(const [method,path,accepted,rejected] of rows){
    resetSettings(s);const marker={method};let reads=0;
    settingsGet(s.defaults,path,()=>{reads++;return marker;});
    for(const value of accepted){settingsWrite(s.data.settings,path,value);expectSettings(s.manager[method]()===value,"strict accepted "+method);}
    expectSettings(reads===0,"strict accepted fallback suppressed");
    for(const value of [...rejected,null,undefined,{},new String(accepted[0])]){
      settingsWrite(s.data.settings,path,value);expectSettings(s.manager[method]()===marker,"strict rejected "+method);
    }
    expectSettings(reads===rejected.length+4,"strict rejection count");
  }
  s.data.settings={outputPad:-0};settingsGet(s.defaults,["outputPad"],()=>{throw new Error("zero fallback");});
  expectSettings(Object.is(s.manager.getOutputPad(),0),"literal positive zero");
  return true;
}
async function observeSettingsShareSetter(s) {
  const value=s.manager.setSessionShareDestination("radius");
  expectSettings(value===undefined,"setter has original void result");
  const flushed=s.manager.flush();await flushed;
  expectSettings(s.manager.getSessionShareDestination()==="radius","actual getter after setter/save");
  expectSettings(s.manager.getGlobalSettings().sessionShareDestination==="radius","actual global storage mutation");
  sameSettings(s.manager.drainErrors(),[],"memory persistence queue succeeds");
  return true;
}
function observeSettingsUnrelated(s) {
  for(const name of Object.keys(s.defaults))Object.defineProperty(s.defaults,name,{configurable:true,get(){throw new Error("unrelated fallback "+name);}});
  s.data.settings={defaultProvider:"real",theme:"dark",enabledModels:["x"],warnings:{first:true},terminal:{images:"kitty",hyperlinks:false}};
  expectSettings(s.manager.getDefaultProvider()==="real","raw field");
  expectSettings(s.manager.getThemeSetting()==="dark","unrelated special field");
  expectSettings(s.manager.getEnabledModels()===s.data.settings.enabledModels,"raw array field");
  sameSettings(s.manager.getWarnings(),{first:true},"ordinary warnings clone");
  sameSettings(s.manager.getTerminalCapabilityOverrides(),{images:"kitty",hyperlinks:false},"unrelated compound no default");
  return true;
}
function observeSettingsNestedParents(s) {
  for(const value of [undefined,null]){
    s.data.settings={terminal:value};s.defaults.terminal={showImages:"live"};
    expectSettings(s.manager.getShowImages()==="live","settings parent optional");
  }
  s.defaults.terminal=null;
  let failed=false;try{s.manager.getShowImages();}catch(e){failed=e instanceof TypeError;}
  expectSettings(failed,"default parent is not optional");
  s.data.settings=null;let rootFailed=false;try{s.manager.getShowImages();}catch(e){rootFailed=e instanceof TypeError;}
  expectSettings(rootFailed,"settings field root is not optional");
  return true;
}
function observeSettingsCacheModes(s) {
  const order=[];const selected={fallback:true};s.defaults.cacheWarming=selected;
  Object.defineProperty(s.modes,"includes",{configurable:true,get(){order.push("get includes");return function(mode){expectSettings(this===s.modes,"actual mode receiver");order.push(mode);return mode==="custom";};}});
  s.data.settings.cacheWarming="streaming";
  expectSettings(s.manager.getCacheWarmingMode()===selected,"only global mode and undefined suppresses includes");
  s.data.global.cacheWarming="custom";expectSettings(s.manager.getCacheWarmingMode()==="custom","mutable exported mode owner");
  s.data.global.cacheWarming=null;expectSettings(s.manager.getCacheWarmingMode()===selected,"null calls includes then fallback");
  sameSettings(order,["get includes","custom","get includes",null],"mode callback order");
  return order;
}
function observeSettingsTreeModes(s) {
  const original=Object.getOwnPropertyDescriptor(Array.prototype,"includes"),seen=[];
  try{
    Object.defineProperty(Array.prototype,"includes",{configurable:true,get(){const array=this;seen.push(array);return function(mode){expectSettings(this===array,"fresh array receiver");return mode==="custom";};}});
    s.data.settings.treeFilterMode=0;s.defaults.treeFilterMode="fallback";
    expectSettings(s.manager.getTreeFilterMode()==="fallback"&&seen.length===0,"false mode suppresses method lookup");
    s.data.settings.treeFilterMode="custom";
    expectSettings(s.manager.getTreeFilterMode()==="custom"&&s.manager.getTreeFilterMode()==="custom","live fresh includes");
  }finally{Object.defineProperty(Array.prototype,"includes",original);}
  expectSettings(seen.length===2&&seen[0]!==seen[1],"one fresh original valid array per invocation");
  sameSettings(seen[0],["default","no-tools","user-only","labeled-only","all"],"exact valid modes");
  return true;
}
function observeSettingsBranchOrder(s) {
  const order=[];let parents=0;
  Object.defineProperty(s.data,"settings",{configurable:true,get(){order.push("settings");return {get branchSummary(){order.push("branch "+(++parents));return parents===1?{reserveTokens:undefined}:{skipPrompt:false};}};}});
  Object.defineProperty(s.defaults,"branchSummary",{configurable:true,get(){order.push("default branch");return {get reserveTokens(){order.push("default reserve");return 7;},get skipPrompt(){throw new Error("unexpected fallback");}};}});
  sameSettings(s.manager.getBranchSummarySettings(),{reserveTokens:7,skipPrompt:false},"branch values");
  sameSettings(order,["settings","branch 1","default branch","default reserve","settings","branch 2"],"repeated original parent Gets");
  return order;
}
function observeSettingsRetryOrder(s) {
  const order=[];let n=0;s.manager.getRetryEnabled=function(){expectSettings(this===s.manager,"live retry receiver");order.push("enabled");return "override";};
  Object.defineProperty(s.data,"settings",{configurable:true,get(){order.push("settings");return {get retry(){order.push("retry "+(++n));return n===1?{maxRetries:2}:n===2?{baseDelayMs:null}:{maxAgentDelayMs:9};}};}});
  Object.defineProperty(s.defaults,"retry",{configurable:true,get(){order.push("default retry");return {get baseDelayMs(){order.push("default delay");return 4;}};}});
  sameSettings(s.manager.getRetrySettings(),{enabled:"override",maxRetries:2,baseDelayMs:4,maxAgentDelayMs:9},"retry values");
  sameSettings(order,["enabled","settings","retry 1","settings","retry 2","default retry","default delay","settings","retry 3"],"live call and repeated retry fields");
  return order;
}
function observeSettingsProviderOrder(s) {
  const order=[];let n=0;
  Object.defineProperty(s.data,"settings",{configurable:true,get(){order.push("settings");return {get retry(){order.push("retry");return {get provider(){order.push("provider "+(++n));return n===1?{timeoutMs:3}:n===2?{maxRetries:undefined}:null;}};}};}});
  Object.defineProperty(s.defaults,"retry",{configurable:true,get(){order.push("default retry");return {get provider(){order.push("default provider");return {get maxRetryDelayMs(){order.push("default delay");return 11;}};}};}});
  const result=s.manager.getProviderRetrySettings();
  expectSettings(result.timeoutMs===3&&Object.hasOwn(result,"maxRetries")&&result.maxRetries===undefined&&result.maxRetryDelayMs===11,"provider fields and own undefined");
  sameSettings(order,["settings","retry","provider 1","settings","retry","provider 2","settings","retry","provider 3","default retry","default provider","default delay"],"provider order");
  return order;
}
function observeSettingsCompactionCalls(s) {
  const order=[],model={provider:"p",id:"m"};
  for(const [name,result] of [["getCompactionEnabled","enabled"],["getCompactionReserveTokens",17],["getCompactionKeepRecentTokens",19]]){
    Object.defineProperty(s.manager,name,{configurable:true,get(){order.push("get "+name);return function(...args){expectSettings(this===s.manager,"actual method receiver");expectSettings(name==="getCompactionEnabled"?args.length===0:args.length===1&&args[0]===model,"original model argument");order.push("call "+name);return result;};}});
  }
  sameSettings(s.manager.getCompactionSettings(model),{enabled:"enabled",reserveTokens:17,keepRecentTokens:19},"compaction values");
  return order;
}
function observeSettingsTokenWrappers(s) {
  const model={},order=[];
  Object.defineProperty(s.manager,"getCompactionTokenSetting",{configurable:true,get(){order.push("get");return function(field,value){expectSettings(this===s.manager&&value===model,"live token wrapper call");order.push(field);return field;};}});
  expectSettings(s.manager.getCompactionReserveTokens(model)==="reserveTokens","reserve wrapper");
  expectSettings(s.manager.getCompactionKeepRecentTokens(model)==="keepRecentTokens","keep wrapper");
  sameSettings(order,["get","reserveTokens","get","keepRecentTokens"],"wrapper field and method order");
  return order;
}
function observeSettingsCapturedTokens(s) {
  const before=s.manager.getCompactionReserveTokens(),other=s.manager.getCompactionKeepRecentTokens();
  s.defaults.compaction.reserveTokens=1;s.defaults.compaction.keepRecentTokens=2;s.defaults.compaction.enabled="live-enabled";
  expectSettings(s.manager.getCompactionReserveTokens()===before&&s.second.getCompactionKeepRecentTokens()===other,"original module captured token defaults");
  expectSettings(s.manager.getCompactionEnabled()==="live-enabled","unrelated compaction enabled fallback remains live");
  return [before,other];
}

function observeSettingsTokenValidation(s) {
  const good=[0,-0,1,9007199254740991];
  for(const value of good){s.data.settings={compaction:{reserveTokens:value}};expectSettings(Object.is(s.manager.getCompactionReserveTokens(),value),"exact valid ordinary");}
  const bad=[null,false,"1",-1,1.5,NaN,Infinity,9007199254740992];
  const messages=[];
  for(const value of bad){
    s.data.settings={compaction:{reserveTokens:value}};
    let reason;try{s.manager.getCompactionReserveTokens();}catch(e){reason=e;}
    expectSettings(reason instanceof Error,"invalid ordinary throws actual Error");
    const expected="Invalid compaction.reserveTokens setting: "+String(value)+". Expected a non-negative safe integer.";
    expectSettings(reason.message===expected,"exact ordinary error message");messages.push(reason.message);
  }
  return messages;
}
function observeSettingsTokenPrecedence(s) {
  const model={provider:"p",id:"m"};
  s.data.settings={compaction:{reserveTokens:3,modelOverrides:{"p/m":{reserveTokens:9}}}};
  expectSettings(s.manager.getCompactionReserveTokens(model)===9,"model override wins");
  s.data.settings.compaction.modelOverrides["p/m"]={};
  expectSettings(s.manager.getCompactionReserveTokens(model)===3,"ordinary fallback");
  s.data.settings.compaction.reserveTokens=null;
  Object.defineProperty(model,"provider",{get(){throw new Error("ordinary must fail before model");}});
  let reason;try{s.manager.getCompactionReserveTokens(model);}catch(e){reason=e;}
  expectSettings(reason.message==="Invalid compaction.reserveTokens setting: null. Expected a non-negative safe integer.","ordinary validation precedes model");
  s.data.settings={compaction:{modelOverrides:{"p/m":{reserveTokens:-2}}}};
  let overrideReason;try{s.manager.getCompactionReserveTokens({provider:"p",id:"m"});}catch(e){overrideReason=e;}
  expectSettings(overrideReason.message==='Invalid compaction.modelOverrides["p/m"].reserveTokens setting: -2. Expected a non-negative safe integer.',"override exact message");
  return true;
}
function observeSettingsTokenKeyOrder(s) {
  const order=[],field={[Symbol.toPrimitive](hint){order.push("field:"+hint);return "reserveTokens";}};
  const model={get provider(){order.push("provider");return {toString(){order.push("provider string");return "p";}};},
    get id(){order.push("id");return {toString(){order.push("id string");return "m";}};}};
  const entry=new Proxy({}, {get(target,key,receiver){order.push("entry:"+String(key));return Reflect.get(target,key,receiver);}});
  s.data.settings={get compaction(){order.push("compaction");return {get reserveTokens(){order.push("ordinary");return undefined;},get modelOverrides(){order.push("overrides");return {"p/m":entry};}};}};
  const actual=s.manager.getCompactionTokenSetting(field,model);
  expectSettings(typeof actual==="number","captured token fallback");
  sameSettings(order,["compaction","field:string","ordinary","provider","provider string","id","id string","overrides","field:string","entry:reserveTokens","field:string"],"optional dynamic key and template coercion order");
  return order;
}
function observeSettingsTokenModelSuppression(s) {
  const order=[],field={[Symbol.toPrimitive](){order.push("key");return "reserveTokens";}};
  s.data.settings={compaction:{get modelOverrides(){throw new Error("false model must suppress overrides");}}};
  for(const model of [false,0,"",null,undefined])expectSettings(typeof s.manager.getCompactionTokenSetting(field,model)==="number","false model skip");
  expectSettings(order.length===10,"only ordinary and fallback keys on false models");
  return order;
}
function observeSettingsEntryValidation(s) {
  const original=Array.isArray,order=[];
  try{
    Array.isArray=function(value){expectSettings(this===Array,"Array.isArray receiver");order.push("isArray");return original(value);};
    for(const value of [null,function(){},[],false,1]){
      s.data.settings={compaction:{modelOverrides:{"p/m":value}}};
      let reason;try{s.manager.getCompactionReserveTokens({provider:"p",id:"m"});}catch(e){reason=e;}
      expectSettings(reason instanceof Error&&reason.message.startsWith('Invalid compaction.modelOverrides["p/m"] setting:'),"bad entry error");
    }
    expectSettings(order.length===1,"only array object enters live Array.isArray");
    Array.isArray=function(value){order.push("permissive");return false;};
    const array=[];array.reserveTokens=7;s.data.settings.compaction.modelOverrides["p/m"]=array;
    expectSettings(s.manager.getCompactionReserveTokens({provider:"p",id:"m"})===7,"live predicate accepted array");
  }finally{Array.isArray=original;}
  return order;
}
function observeSettingsErrorOrder(s) {
  const originalError=Object.getOwnPropertyDescriptor(globalThis,"Error"),originalString=Object.getOwnPropertyDescriptor(globalThis,"String"),order=[];
  const errorMarker={selected:true};
  const raw={toString(){order.push("raw toString");return "raw";}};
  const field={[Symbol.toPrimitive](hint){order.push("field:"+hint);return "reserveTokens";}};
  s.data.settings={compaction:{reserveTokens:raw}};
  try{
    Object.defineProperty(globalThis,"Error",{configurable:true,get(){order.push("Error");return function(message){order.push("construct:"+message);return errorMarker;};}});
    Object.defineProperty(globalThis,"String",{configurable:true,get(){order.push("String");return function(value){expectSettings(this===undefined&&value===raw,"String actual argument");order.push("String call");return {toString(){order.push("display stringify");return "display";}};};}});
    let observed;try{s.manager.getCompactionTokenSetting(field);}catch(e){observed=e;}
    expectSettings(observed===errorMarker,"actual constructed reason");
  }finally{Object.defineProperty(globalThis,"Error",originalError);Object.defineProperty(globalThis,"String",originalString);}
  sameSettings(order,["field:string","Error","field:string","String","String call","display stringify","construct:Invalid compaction.reserveTokens setting: display. Expected a non-negative safe integer."],"error callee before original template/String coercions");
  return order;
}
function observeSettingsThrownPredicates(s) {
  const original=Number.isSafeInteger,sentinel={same:true},order=[];
  try{
    Number.isSafeInteger=function(value){order.push(value);throw sentinel;};
    s.data.settings={compaction:{reserveTokens:1, get modelOverrides(){throw new Error("later field");}}};
    let observed;try{s.manager.getCompactionReserveTokens({get provider(){throw new Error("later model");}});}catch(e){observed=e;}
    expectSettings(observed===sentinel,"predicate pending identity");
  }finally{Number.isSafeInteger=original;}
  sameSettings(order,[1],"one predicate call");
  return order;
}
function observeSettingsWidthOrder(s) {
  const savedNumber=Object.getOwnPropertyDescriptor(globalThis,"Number"),savedMath=Object.getOwnPropertyDescriptor(globalThis,"Math"),order=[];
  const marker={final:true};
  const numberOwner={get isFinite(){order.push("isFinite");return function(value){expectSettings(this===numberOwner&&value===3.8,"finite receiver/value");order.push("finite call");return true;};}};
  let mathCount=0;
  const maxOwner={get max(){order.push("max");return function(a,b){expectSettings(this===maxOwner&&a===1&&b===3,"max receiver/args");order.push("max call");return marker;};}};
  const floorOwner={get floor(){order.push("floor");return function(value){expectSettings(this===floorOwner&&value===3.8,"floor receiver/arg");order.push("floor call");return 3;};}};
  s.data.settings={terminal:{imageWidthCells:3.8}};
  try{
    Object.defineProperty(globalThis,"Number",{configurable:true,get(){order.push("Number");return numberOwner;}});
    Object.defineProperty(globalThis,"Math",{configurable:true,get(){order.push("Math");return ++mathCount===1?maxOwner:floorOwner;}});
    expectSettings(s.manager.getImageWidthCells()===marker,"actual Math result forwarded");
  }finally{Object.defineProperty(globalThis,"Number",savedNumber);Object.defineProperty(globalThis,"Math",savedMath);}
  sameSettings(order,["Number","isFinite","finite call","Math","max","Math","floor","floor call","max call"],"outer callee before nested argument");
  return order;
}
function observeSettingsWheelOrder(s) {
  const saved=Object.getOwnPropertyDescriptor(globalThis,"Math"),order=[],owners=[];
  const max={get max(){order.push("max get");return function(a,b){expectSettings(this===max&&a===1&&b===100,"max args");order.push("max call");return 100;};}};
  const min={get min(){order.push("min get");return function(a,b){expectSettings(this===min&&a===100&&b===130,"min args");order.push("min call");return 100;};}};
  const floor={get floor(){order.push("floor get");return function(value){expectSettings(this===floor&&value===130.7,"floor args");order.push("floor call");return 130;};}};
  owners.push(max,min,floor);let i=0;s.data.settings={fullscreenWheelScrollLines:130.7};
  try{Object.defineProperty(globalThis,"Math",{configurable:true,get(){order.push("Math");return owners[i++];}});expectSettings(s.manager.getFullscreenWheelScrollLines()===100,"bounded wheel result");}
  finally{Object.defineProperty(globalThis,"Math",saved);}
  sameSettings(order,["Math","max get","Math","min get","Math","floor get","floor call","min call","max call"],"nested original math order");
  return order;
}
function observeSettingsNumericFallback(s) {
  const original=Number.isFinite,order=[];
  s.defaults.terminal.imageWidthCells="live-width";s.defaults.fullscreenWheelScrollLines="live-wheel";
  try{
    Number.isFinite=function(value){order.push(value);return false;};
    for(const value of ["3",null,undefined,{},false]){
      s.data.settings={terminal:{imageWidthCells:value},fullscreenWheelScrollLines:value};
      expectSettings(s.manager.getImageWidthCells()==="live-width"&&s.manager.getFullscreenWheelScrollLines()==="live-wheel","non-number fallback");
    }
    expectSettings(order.length===0,"typeof suppresses global numeric call");
    s.data.settings={terminal:{imageWidthCells:2},fullscreenWheelScrollLines:3};
    expectSettings(s.manager.getImageWidthCells()==="live-width"&&s.manager.getFullscreenWheelScrollLines()==="live-wheel","false live predicate");
  }finally{Number.isFinite=original;}
  sameSettings(order,[2,3],"live numeric predicate only on numbers");
  return order;
}
function observeSettingsClearOrder(s) {
  const order=[];let reads=0;
  Object.defineProperty(s.data,"settings",{configurable:true,get(){order.push("settings");return {get terminal(){order.push("terminal");return {get clearOnShrink(){order.push("clear "+(++reads));return reads===1?null:"second";}};}};}});
  expectSettings(s.manager.getClearOnShrink()==="second","defined null causes original second read");
  sameSettings(order,["settings","terminal","clear 1","settings","terminal","clear 2"],"clear defined branch rereads");
  Object.defineProperty(s.data,"settings",{configurable:true,value:{},writable:true});
  s.defaults.terminal.clearOnShrink="live-clear";
  const old=Object.getOwnPropertyDescriptor(process.env,"PI_CLEAR_ON_SHRINK");
  try{
    Object.defineProperty(process.env,"PI_CLEAR_ON_SHRINK",{configurable:true,writable:true,value:"1"});expectSettings(s.manager.getClearOnShrink()===true,"literal env one");
    process.env.PI_CLEAR_ON_SHRINK=1;expectSettings(s.manager.getClearOnShrink()==="live-clear","number one does not match");
    process.env.PI_CLEAR_ON_SHRINK="0";expectSettings(s.manager.getClearOnShrink()==="live-clear","env false live fallback");
  }finally{if(old)Object.defineProperty(process.env,"PI_CLEAR_ON_SHRINK",old);else delete process.env.PI_CLEAR_ON_SHRINK;}
  return order;
}
function observeSettingsGetterFailure(s) {
  const sentinel={pending:true},order=[];
  Object.defineProperty(s.data.settings,"transport",{get(){order.push("settings");throw sentinel;}});
  settingsGet(s.defaults,["transport"],()=>{order.push("default");throw new Error("later fallback");});
  let observed;try{s.manager.getTransport();}catch(e){observed=e;}
  expectSettings(observed===sentinel,"original pending identity");sameSettings(order,["settings"],"abrupt getter suppresses fallback");
  return order;
}
function observeSettingsPrivateData(s,h) {
  const data=h.freshPrivateData();s.defaults.transport=data;
  expectSettings(s.manager.getTransport()===data&&h.isUnmarkedPrivateData(data),"successful actual private Error remains ordinary data");
  return true;
}
function observeSettingsTemporaryOrder(s,h) {
  const order=[];
  s.data.settings={get terminal(){const parent=h.make(0);Object.defineProperty(parent,"showImages",{get(){order.push(["field",h.count(0)]);return undefined;}});return parent;}};
  Object.defineProperty(s.defaults,"terminal",{configurable:true,get(){order.push(["default parent",h.count(0)]);const parent=h.make(1);Object.defineProperty(parent,"showImages",{get(){order.push(["default field",h.count(1)]);return true;}});return parent;}});
  expectSettings(s.manager.getShowImages()===true,"temporary path result");
  order.push(["returned",h.count(0),h.count(1)]);
  return order;
}
function observeSettingsLocalOrder(s,h) {
  const order=[];
  s.data.settings={get sessionShareDestination(){return h.make(0);}};
  settingsGet(s.defaults,["sessionShareDestination"],()=>{order.push(["fallback",h.count(0)]);return "auto";});
  expectSettings(s.manager.getSessionShareDestination()==="auto","local fallback");
  order.push(["returned",h.count(0)]);
  return order;
}
function observeSettingsComparisonOrder(s,h) {
  const order=[];
  s.data.settings={get tuiMode(){return h.make(0);}};
  settingsGet(s.defaults,["tuiMode"],()=>{order.push(["fallback",h.count(0)]);return "fullscreen";});
  expectSettings(s.manager.getTuiMode()==="fullscreen","temporary comparison fallback");
  order.push(["returned",h.count(0)]);
  return order;
}
function observeSettingsPredicateOrder(s,h) {
  const saved=Number.isFinite,savedMath=Object.getOwnPropertyDescriptor(globalThis,"Math"),order=[];
  const actualMath=Math;s.data.settings={terminal:{imageWidthCells:4}};
  try{
    Number.isFinite=()=>h.make(0);
    Object.defineProperty(globalThis,"Math",{configurable:true,get(){order.push(["Math",h.count(0)]);return actualMath;}});
    expectSettings(s.manager.getImageWidthCells()===4,"truthy predicate result");
  }finally{Number.isFinite=saved;Object.defineProperty(globalThis,"Math",savedMath);}
  order.push(["returned",h.count(0)]);return order;
}
function observeSettingsTokenLocalOrder(s,h) {
  const order=[];
  const model={provider:"p",id:"m"};
  s.data.settings={get compaction(){const compaction=h.make(0);compaction.reserveTokens=3;compaction.modelOverrides={"p/m":{reserveTokens:5}};return compaction;}};
  const saved=Number.isSafeInteger;
  try{Number.isSafeInteger=function(value){order.push([value,h.count(0),h.count(1)]);return true;};
    s.manager.getCompactionTokenSetting("reserveTokens",model,h.make(1));
  }finally{Number.isSafeInteger=saved;}
  order.push(["returned",h.count(0),h.count(1)]);return order;
}
function observeSettingsCurrentFatal(s,h) {
  h.freshPrivateData();
  settingsGet(s.defaults,["transport"],()=>{h.raiseNativeFatal();h.visit(1);return "never";});
  try{s.manager.getTransport();}catch(e){h.visit(3);}
  h.visit(2);
}
function observeSettingsRetirementFatal(s,h) {
  h.armFatal(0);
  s.data.settings={get terminal(){const value=h.make(0);value.showImages=undefined;return value;}};
  settingsGet(s.defaults,["terminal","showImages"],()=>{h.visit(1);return true;});
  try{s.manager.getShowImages();}catch(e){h.visit(3);}
  h.visit(2);
}
function observeSettingsRetirementCancel(s,h) {
  h.armCancel(0);
  s.data.settings={get terminal(){const value=h.make(0);value.showImages=undefined;return value;}};
  settingsGet(s.defaults,["terminal","showImages"],()=>{h.visit(1);return true;});
  try{s.manager.getShowImages();}catch(e){h.visit(3);}
  h.visit(2);
}

"use strict";
const mhPush = Array.prototype.push;
const mhError = Error;
function mhAssert(value, message) { if (!value) throw new mhError(message); }
function mhLog(value) { Reflect.apply(mhPush, __mhTrace, [value]); }
function mhModel(id="a", provider="control") { return { id, provider, type:"chat", name:id }; }
// Intentional caller values for these pure function formals. Imported
// AI/resolver/paths and SettingsManager are the actual native production owners.
function mhRuntime(models) {
  return {
    getModels(){mhLog("getModels");return models;},
    hasConfiguredAuth(){return true;},
    getModel(provider,id){mhLog("getModel:"+provider+"/"+id);return models.find(m=>m.provider===provider&&m.id===id);},
  };
}
function mhSettings(provider, id) {
  const receiver=__mhSettings;
  receiver.getDefaultProvider=function(){mhAssert(this===receiver,"settings provider receiver");mhLog("saved-provider");return provider;};
  receiver.getDefaultModel=function(){mhAssert(this===receiver,"settings model receiver");mhLog("saved-model");return id;};
  return receiver;
}
function mhPrepare(name) {
  globalThis.__mhTrace=[];
  globalThis.__mhState={};
  if (["cli-order","cli-repeat","cli-explicit","cli-no-model","boolean-live","capture-imports","options-setter","resolved-lifetime","boolean-lifetime"].includes(name)) {
    __mhResolver.resolveCliModel=function(options) {
      mhAssert(this===undefined,"named resolver receiver");
      mhLog("resolve");
      __mhState.resolveOptions=options;
      if(name==="boolean-lifetime") { __mhGC(); mhLog("resolve-count:"+__mhHooks.count(0)); }
      if(name==="resolved-lifetime") {
        const row=__mhHooks.make(0);
        row.model=mhModel(); row.warning=undefined; row.error=undefined;
        return row;
      }
      if(name==="cli-repeat") {
        let warning=0,error=0,model=0,thinking=0;
        return {
          get warning(){mhLog("warning");return ++warning===1?"check-warning":"output-warning";},
          get error(){mhLog("error");return ++error===1?"check-error":"output-error";},
          get model(){mhLog("resolved-model");return ++model===1?mhModel("test"):mhModel("assigned");},
          get thinkingLevel(){mhLog("resolved-thinking");return ++thinking===1?"test-thinking":"assigned-thinking";},
        };
      }
      if(name==="cli-no-model") return {model:undefined,thinkingLevel:"high"};
      return {model:mhModel("cli"),thinkingLevel:"high"};
    };
  }
  if(name==="capture-imports") {
    __mhModels.modelsAreEqual=function(a,b){mhAssert(this===undefined,"named equality receiver");mhLog("equal-captured");return a.id===b.id;};
  }
  if(["path-capture","path-escape","path-throw-escape","path-order","cwd-lifetime"].includes(name)) {
    __mhPaths.isLocalPath=function(value){mhAssert(this===undefined,"named path predicate receiver");mhLog("isLocal");return value.local;};
    __mhPaths.resolvePath=function(value,cwd){mhAssert(this===undefined,"named path resolver receiver");mhLog("resolvePath");return {value,cwd};};
  }
}
function mhObserve(name, subject) {
  const build=subject.buildSessionOptions, paths=subject.resolveCliPaths;
  let value;
  const a=mhModel(), b=mhModel("b");
  if(name==="shapes") {
    mhAssert(build.name==="buildSessionOptions"&&build.length===5,"build shape");
    mhAssert(paths.name==="resolveCliPaths"&&paths.length===2,"paths shape");
    mhAssert(Object.hasOwn(build,"prototype")&&Object.hasOwn(paths,"prototype"),"ordinary functions");
    mhAssert(Object.keys(subject).join(",")==="buildSessionOptions,resolveCliPaths","complete pair");
    value=[Object.getPrototypeOf(build)===Function.prototype,Object.getPrototypeOf(paths)===Function.prototype,
      Object.keys(new build({},[],false,{},__mhSettings)).join(",")];
  } else if(name==="empty") {
    value=build({},[],false,{},__mhSettings);
    mhAssert(Object.keys(value.options).length===0&&value.diagnostics.length===0&&!value.cliThinkingFromModel,"empty original result");
  } else if(name==="provider-required") {
    let providerReads=0,modelReads=0;
    const parsed={get provider(){mhLog("provider");return ++providerReads===1?"test":"output";},
      get model(){mhLog("model");modelReads++;return undefined;}};
    value=build(parsed,[],false,{},__mhSettings);
    mhAssert(value.diagnostics[0].message==="--provider requires --model (for example: --provider output --model <pattern>)","repeated provider message");
    mhAssert(providerReads===2&&modelReads===2,"original condition reads");
  } else if(name==="cli-actual") {
    const runtime=mhRuntime([a,b]);
    value=build({provider:"control",model:"b",thinking:"medium",apiKey:"key"},[],false,runtime,__mhSettings);
    mhAssert(value.options.model===b&&value.options.thinkingLevel==="medium"&&!value.cliThinkingFromModel,"actual resolver selection");
  } else if(name==="cli-order") {
    const parsed=new Proxy({provider:"p",model:"m",thinking:undefined,apiKey:0},{get(target,key){mhLog("parsed."+String(key));return target[key];}});
    value=build(parsed,[],false,{},__mhSettings);
    mhAssert(value.options.model.id==="cli"&&value.options.thinkingLevel==="high"&&value.cliThinkingFromModel,"CLI fields");
    mhAssert(Object.keys(__mhState.resolveOptions).join(",")==="cliProvider,cliModel,cliThinking,inlineApiKey,modelRuntime","CLI object field order");
  } else if(name==="cli-repeat") {
    value=build({model:"m"},[],false,{},__mhSettings);
    mhAssert(value.diagnostics[0].message==="output-warning"&&value.diagnostics[1].message==="output-error","repeated diagnostic Gets");
    mhAssert(value.options.model.id==="assigned"&&value.options.thinkingLevel==="assigned-thinking"&&value.cliThinkingFromModel,"repeated model/thinking Gets");
  } else if(name==="cli-explicit") {
    let reads=0;
    const parsed={model:"m",get thinking(){mhLog("thinking");return ++reads===3?"late":"explicit";}};
    value=build(parsed,[],false,{},__mhSettings);
    mhAssert(!value.cliThinkingFromModel&&value.options.thinkingLevel==="explicit","explicit CLI precedence");
  } else if(name==="cli-no-model") {
    value=build({model:"m"},[],false,{},__mhSettings);
    mhAssert(!Object.hasOwn(value.options,"thinkingLevel")&&!value.cliThinkingFromModel,"thinking requires resolved model");
  } else if(name==="boolean-live") {
    const old=Object.getOwnPropertyDescriptor(globalThis,"Boolean");
    const marker={marker:"boolean-result"};
    Object.defineProperty(globalThis,"Boolean",{configurable:true,get(){mhLog("Boolean.get");return function(value){mhAssert(this===undefined,"Boolean receiver");mhLog("Boolean.call");mhAssert(value==="input","api key");return marker;};}});
    try {
      value=build({model:"m",get apiKey(){mhLog("apiKey.get");return "input";}},[],false,{},__mhSettings);
      mhAssert(__mhState.resolveOptions.inlineApiKey===marker,"live Boolean result preserved");
    } finally {Object.defineProperty(globalThis,"Boolean",old);}
  } else if(name==="saved-model") {
    const scope=[{model:a,thinkingLevel:"low"},{model:b,thinkingLevel:"high"}];
    value=build({},scope,false,mhRuntime([a,b]),mhSettings("control","b"));
    mhAssert(value.options.model===b&&value.options.thinkingLevel==="high","saved model in scope");
    mhAssert(value.options.scopedModels!==scope&&value.options.scopedModels[1]!==scope[1],"scope mapping");
  } else if(name==="saved-false") {
    value=build({},[{model:a}],false,mhRuntime([a]),mhSettings("", "a"));
    mhAssert(value.options.model===a&&__mhTrace.join(",")==="saved-provider,saved-model","both settings calls, no getModel");
  } else if(name==="saved-missing") {
    value=build({},[{model:a,thinkingLevel:"low"}],false,mhRuntime([a]),mhSettings("control","missing"));
    mhAssert(value.options.model===a&&value.options.thinkingLevel==="low","first model fallback");
  } else if(name==="existing-session") {
    __mhSettings.getDefaultProvider=()=>{throw new mhError("must suppress settings");};
    value=build({},[{model:a}],{},null,__mhSettings);
    mhAssert(!Object.hasOwn(value.options,"model")&&value.options.scopedModels[0].model===a,"existing session still maps scope");
  } else if(name==="first-repeat") {
    let zero=0;
    const scope={length:1,get 0(){mhLog("index");return {model:a,thinkingLevel:++zero===2?"test":"assigned"};},
      map(callback){mhAssert(this===scope,"map receiver");return [callback({model:b})];}};
    value=build({},scope,false,mhRuntime([a]),mhSettings(undefined,undefined));
    mhAssert(zero===3&&value.options.thinkingLevel==="assigned"&&value.options.model===a,"repeated first element reads");
  } else if(name==="length-live") {
    let reads=0;
    const scope={get length(){mhLog("length");return ++reads===1?0:1;},
      map(callback){mhLog("map");return [callback({model:b})];}};
    value=build({},scope,false,null,__mhSettings);
    mhAssert(!Object.hasOwn(value.options,"model")&&value.options.scopedModels[0].model===b&&reads===2,"length reread");
  } else if(name==="scope-map-escape") {
    let saved;
    const scope={length:1,map(callback){saved=callback;return "mapped";}};
    value=build({},scope,true,null,__mhSettings);
    mhAssert(value.options.scopedModels==="mapped"&&!Object.hasOwn(saved,"prototype")&&saved.length===1,"actual escaping arrow");
    let reads=[];
    const row=saved({get model(){reads.push("model");return a;},get thinkingLevel(){reads.push("thinking");return undefined;}});
    mhAssert(Object.keys(row).join(",")==="model,thinkingLevel"&&reads.join(",")==="model,thinking","map literal order");
    value={mapped:value.options.scopedModels,keys:Object.keys(row),same:row.model===a};
  } else if(name==="find-escape"||name==="find-throw-escape") {
    let saved;const failure={failure:1};
    const scope={length:1,find(callback){saved=callback;if(name==="find-throw-escape")throw failure;return undefined;},0:{model:a},map(){return [];}};
    let caught;
    try {value=build({},scope,false,mhRuntime([a]),mhSettings("control","a"));}catch(error){caught=error;}
    if(name==="find-throw-escape")mhAssert(caught===failure,"exact find failure");
    mhAssert(!Object.hasOwn(saved,"prototype")&&saved.length===1&&saved({model:a})&& !saved({model:b}),"saved lexical cell after return or throw");
    value={thrown:caught===failure,match:saved({model:a}),miss:saved({model:b})};
  } else if(name==="capture-imports") {
    __mhResolver.resolveCliModel=()=>{throw new mhError("late resolver member");};
    __mhModels.modelsAreEqual=()=>{throw new mhError("late equality member");};
    const first=build({model:"x"},[],false,{},__mhSettings);
    const second=build({},[{model:a}],false,mhRuntime([a]),mhSettings("control","a"));
    mhAssert(first.options.model.id==="cli"&&second.options.model===a,"once-only imported captures");
    value=[first.options.model.id,second.options.model.id];
  } else if(name==="options-setter") {
    const old=Object.getOwnPropertyDescriptor(Object.prototype,"model");
    let assigned;
    Object.defineProperty(Object.prototype,"model",{configurable:true,set(value){mhLog("model.set");assigned=value;},get(){mhLog("model.get");return assigned;}});
    try {
      value=build({model:"x"},[],false,{},__mhSettings);
      mhAssert(!Object.hasOwn(value.options,"model")&&assigned.id==="cli","ordinary option Set retained");
      value={own:Object.keys(value.options),assigned:assigned.id,thinking:value.options.thinkingLevel};
    }finally{if(old)Object.defineProperty(Object.prototype,"model",old);else delete Object.prototype.model;}
  } else if(name==="tools-precedence") {
    const parsed={noTools:true,get noBuiltinTools(){throw new mhError("suppressed lower priority");},tools:["a"],excludeTools:["b"]};
    value=build(parsed,[],false,{},__mhSettings);
    mhAssert(value.options.noTools==="all"&&value.options.tools!==parsed.tools&&value.options.excludeTools!==parsed.excludeTools,"tool options copies");
  } else if(name==="builtin-only") {
    value=build({noTools:0,noBuiltinTools:1},[],false,{},__mhSettings);
    mhAssert(value.options.noTools==="builtin","builtin exclusion");
  } else if(name==="spread-order") {
    let getter=0,next=0;
    const iterable={get [Symbol.iterator](){mhLog("iterator.get");return function(){mhLog("iterator.call");return {get next(){mhLog("next.get");return function(){mhLog("next.call");return next++?{done:true}:{done:false,value:"tool"};};}};};}};
    const parsed={get tools(){mhLog("tools.get");return ++getter===1?true:iterable;}};
    value=build(parsed,[],false,{},__mhSettings);
    mhAssert(value.options.tools.join(",")==="tool"&&getter===2,"spread second property Get");
    mhAssert(__mhTrace.filter(x=>x==="iterator.get").length===2,"actual OP_append iterator reads");
  } else if(["spread-next-failure","spread-done-failure","spread-value-failure"].includes(name)) {
    const failure={name};let closed=0;
    const iterable={[Symbol.iterator](){return {next(){if(name==="spread-next-failure")throw failure;return {get done(){if(name==="spread-done-failure")throw failure;return false;},get value(){throw failure;}};},return(){closed++;mhLog("return");throw new mhError("displaced close");}};}};
    let caught;try{build({tools:iterable,get excludeTools(){throw new mhError("later property");}},[],false,{},__mhSettings);}catch(error){caught=error;}
    mhAssert(caught===failure&&closed===1,"actual append closes on step failure and preserves throw");
    value={caught:caught===failure,closed};
  } else if(name==="spread-getnext-failure") {
    const failure={};let closed=0;
    const iterable={[Symbol.iterator](){return {get next(){throw failure;},return(){closed++;}};}};
    let caught;try{build({tools:iterable},[],false,{},__mhSettings);}catch(error){caught=error;}
    mhAssert(caught===failure&&closed===0,"Get(next) failure does not enter append close region");
    value={caught:caught===failure,closed};
  } else if(name==="spread-noniterable") {
    let read=0,later=0,caught;
    try{build({get tools(){return ++read===1?true:7;},get excludeTools(){later++;}},[],false,{},__mhSettings);}catch(error){caught=error;}
    mhAssert(caught instanceof TypeError&&read===2&&later===0,"noniterable abort ordering");
    value={type:caught.name,read,later};
  } else if(name==="path-nullish") {
    mhAssert(paths("cwd",undefined)===undefined&&paths("cwd",null)===undefined,"nullish suppression");
    let caught;try{paths("cwd",false);}catch(error){caught=error;}
    mhAssert(caught instanceof TypeError,"falsy does not mean optional");
    value=caught.name;
  } else if(name==="path-actual") {
    const input=["./local","npm:package","https://example.invalid/tool","git:repository"];
    const output=paths(__mhDisk,input);
    mhAssert(output!==input&&output[0]===__mhNodePath.resolve(__mhDisk,"./local"),"actual local path");
    mhAssert(output.slice(1).join("|")===input.slice(1).join("|"),"nonlocal input identity");
    value=[true,...output.slice(1)];
  } else if(name==="path-holes") {
    const input=[];input.length=3;input[1]="npm:x";
    const output=paths(__mhDisk,input);
    mhAssert(output.length===3&&!(0 in output)&&output[1]==="npm:x"&&!(2 in output),"actual map holes");
    value=Object.keys(output);
  } else if(name==="path-capture") {
    __mhPaths.isLocalPath=()=>{throw new mhError("late predicate");};
    __mhPaths.resolvePath=()=>{throw new mhError("late resolver");};
    const cwd={},local={local:true},remote={local:false};
    const output=paths(cwd,[local,remote]);
    mhAssert(output[0].value===local&&output[0].cwd===cwd&&output[1]===remote,"one-time real named path captures");
    value=[true,true,true];
  } else if(name==="path-order") {
    const cwd={};let callback;
    const input={get map(){mhLog("map.get");return function(value){mhAssert(this===input,"actual map receiver");mhLog("map.call");callback=value;return "arbitrary-map-result";};}};
    mhAssert(paths(cwd,input)==="arbitrary-map-result","live arbitrary map return");
    const valueIn={get local(){mhLog("local.get");return true;}};
    const output=callback(valueIn);
    mhAssert(output.value===valueIn&&output.cwd===cwd,"callback formals");
    value=__mhTrace.slice();
  } else if(name==="path-escape"||name==="path-throw-escape") {
    const cwd={name:"actual cwd"};let callback;const failure={};
    const input={map(value){callback=value;if(name==="path-throw-escape")throw failure;return undefined;}};
    let caught;try{paths(cwd,input);}catch(error){caught=error;}
    if(name==="path-throw-escape")mhAssert(caught===failure,"map thrown identity");
    const inputValue={local:true};const output=callback.call({},inputValue);
    mhAssert(output.value===inputValue&&output.cwd===cwd&&!Object.hasOwn(callback,"prototype"),"detached actual cwd formal");
    value={caught:caught===failure,same:output.cwd===cwd,arity:callback.length};
  } else {
    return mhObserveLifetime(name,subject);
  }
  return {value,trace:__mhTrace};
}

function mhObserveLifetime(name,subject) {
  const build=subject.buildSessionOptions,paths=subject.resolveCliPaths,h=__mhHooks;
  let value;
  if(name==="actual-settings") {
    const a=mhModel(),b=mhModel("b");
    __mhSettings.setDefaultProvider("control");
    __mhSettings.setDefaultModel("b");
    value=build({},[{model:a},{model:b}],false,mhRuntime([a,b]),__mhSettings);
    mhAssert(value.options.model===b,"actual SettingsManager accessors");
  } else if(name==="resolved-lifetime") {
    value=build({model:"x",get noTools(){__mhGC();mhLog("during:"+h.count(0));return false;}},[],false,{},__mhSettings);
    __mhGC();
    mhAssert(h.count(0)===1,"resolved block local retires at function terminal");
    value={during:__mhTrace.includes("during:0"),after:h.count(0),model:value.options.model.id};
  } else if(name==="condition-lifetime") {
    let providers=0;
    value=build({get provider(){return ++providers===1?h.make(0):"p";},
      get model(){__mhGC();mhLog("model-count:"+h.count(0));return undefined;}},[],false,{},__mhSettings);
    __mhGC();mhAssert(h.count(0)===1,"condition temporary retired");
    value={count:h.count(0),diagnostics:value.diagnostics.length};
  } else if(name==="boolean-lifetime") {
    const old=Boolean;
    globalThis.Boolean=function(value){mhLog("Boolean-count:"+h.count(0));return false;};
    try{value=build({model:"m",get apiKey(){return h.make(0);}},[],false,{},__mhSettings);}
    finally{globalThis.Boolean=old;}
    __mhGC();mhAssert(h.count(0)===1,"Boolean argument retired before resolution");
    value={count:h.count(0),model:value.options.model.id};
  } else if(name==="extra-argument-lifetime") {
    value=build.call(h.make(0),{get noTools(){__mhGC();mhLog("body:"+h.count(0)+":"+h.count(1));return false;}},
      [],false,{},__mhSettings,h.make(1));
    __mhGC();mhAssert(h.count(0)===1&&h.count(1)===1,"actual receiver and extra argument retire");
    value={counts:[h.count(0),h.count(1)],empty:Object.keys(value.options).length===0};
  } else if(name==="saved-binding-lifetime"||name==="saved-binding-abrupt-lifetime") {
    const a=mhModel();const failure={};
    const runtime={getModel(){const saved=h.make(0);saved.id=a.id;saved.provider=a.provider;return saved;}};
    const scope={length:1,0:{model:a},find(callback){globalThis.__mhEscaped=callback;
      if(name==="saved-binding-abrupt-lifetime")throw failure;return undefined;},map(){return [];}};
    let caught;try{build({},scope,false,runtime,mhSettings("control","a"));}catch(error){caught=error;}
    if(name==="saved-binding-abrupt-lifetime")mhAssert(caught===failure,"exact abrupt capture");
    __mhGC();mhAssert(h.count(0)===0&&__mhEscaped({model:a}),"escaped savedModel cell remains live");
    globalThis.__mhEscaped=undefined;__mhGC();
    mhAssert(h.count(0)===1,"savedModel cell closes without keeping whole activation");
    value={caught:caught===failure,after:h.count(0)};
  } else if(name==="cwd-lifetime") {
    const input={map(callback){globalThis.__mhEscaped=callback;return null;}};
    mhAssert(paths(h.make(0),input)===null,"map return");
    __mhGC();mhAssert(h.count(0)===0,"escaped cwd parameter kept");
    __mhEscaped({local:true});
    globalThis.__mhEscaped=undefined;__mhGC();
    mhAssert(h.count(0)===1,"cwd parameter detached and retired");
    value=h.count(0);
  } else if(name==="actual-private-data") {
    const data=h.freshPrivateData();let caught;
    try{build({get provider(){throw data;}},[],false,{},__mhSettings);}catch(error){caught=error;}
    mhAssert(caught===data&&h.isUnmarkedPrivateData(caught),"unmarked native DATA remains catchable");
    value={caught:true,private:true};
  } else throw new mhError("unknown control "+name);
  return {value,trace:__mhTrace};
}
function mhFatal(kind,subject) {
  const h=__mhHooks;
  if(kind==="current") {
    h.freshPrivateData();
    try{subject.buildSessionOptions({get provider(){h.raiseNativeFatal();h.visit(1);}},[],false,{},__mhSettings);}catch(error){h.visit(3);}
  } else {
    if(kind==="retirement")h.armFatal(0);else h.armCancel(0);
    try{subject.buildSessionOptions({get provider(){return h.make(0);},get model(){h.visit(1);}},[],false,{},__mhSettings);}catch(error){h.visit(3);}
  }
  h.visit(2);
}

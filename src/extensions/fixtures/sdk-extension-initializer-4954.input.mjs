// User-style controls over actual original/composed loader functions and runtime.
const {loader,eventBus:events,sourceInfo}=globalThis.ActualExtensionInitializer;
const cwd=globalThis.ActualExtensionFixtureDir;
if(typeof cwd!=='string'||!cwd)throw Error('Explicit owned fixture directory required');
const rows=[];const add=(name,value)=>rows.push({name,value});
const portable=value=>typeof value==='string'?value.split(cwd).join('<fixture>'):value;
const thrown=fn=>{try{fn();return null}catch(error){return {name:error?.name,message:portable(error?.message)}}};
const tick=()=>new Promise(resolve=>queueMicrotask(resolve));
add('source-information-path-cases',['builtin:read','<inline:named>','<>','<open','disk/file.ts'].map(path=>({path,source:sourceInfo.getSyntheticPathSource(path)??null,synthetic:sourceInfo.isSyntheticPath(path)})));
add('source-information-order-defaults',{keys:Object.keys(sourceInfo.createSyntheticSourceInfo('<inline>',{source:'inline'})),value:sourceInfo.createSyntheticSourceInfo('<inline>',{source:'inline'})});
add('initializer-function-metadata',{name:loader.loadExtensionFromFactory.name,length:loader.loadExtensionFromFactory.length});
const runtime=loader.createExtensionRuntime();const bus=events.createEventBus();
add('actual-runtime-field-order',Object.keys(runtime));
let api,off;const trace=[];let handlerCalls=0;
const tool={get parameters(){trace.push('schema');return {type:'object',properties:{}}},get name(){trace.push('name');return 'fixture-tool'},execute:async()=>({content:[]})};
const extension=await loader.loadExtensionFromFactory(async pi=>{
  api=pi;
  pi.registerTool(tool);pi.registerCommand('fixture-command',{description:'fixture',handler:()=>undefined});
  pi.registerShortcut('ctrl+z',{description:'fixture',handler:()=>undefined});
  pi.registerFlag('mode',{type:'string',default:'first'});pi.registerFlag('mode',{type:'string',default:'second'});
  add('loading-flag-private-pending',{api:pi.getFlag('mode'),runtimeHas:runtime.flagValues.has('mode')});
  pi.registerProvider('fixture-provider',{baseUrl:'https://example.test',apiKey:'fixture-user-input'});
  pi.registerMcpServer('fixture-mcp',{command:'never-executed-reference-fixture',args:[]});
  pi.registerVirtualModel({provider:'fixture-virtual',id:'route',route:()=>undefined});
  add('loading-runtime-queues',{providers:runtime.pendingProviderRegistrations.length,mcp:runtime.mcpServers.list().length,virtual:runtime.pendingVirtualModelRegistrations.length});
  off=pi.on('fixture-event',(...args)=>{handlerCalls++;return args[0]});
  pi.registerMessageRenderer('fixture',()=>undefined);pi.registerEntryRenderer('fixture',()=>undefined);
  pi.registerMarkdownTransformer(value=>value);pi.registerToolRenderer(()=>undefined);
  pi.events.on('fixture-bus',()=>{trace.push('bus')});
  pi.events.emit('fixture-bus',{fixture:true});
  await tick();
},cwd,bus,runtime,'<inline:actual>');
const registeredHandler=extension.handlers.get('fixture-event')[0];const handlerMarker={handler:true};
const handlerIdentity=registeredHandler.call({ignored:true},handlerMarker,2)===handlerMarker;
off();off();
add('created-extension-order',{keys:Object.keys(extension),path:extension.path,resolvedPath:extension.resolvedPath,sourceInfo:extension.sourceInfo});
add('tool-getter-order',trace.filter(value=>value!=='bus'));
add('registration-map-identities',{tool:extension.tools.get('fixture-tool').definition===tool,toolSource:extension.tools.get('fixture-tool').sourceInfo===extension.sourceInfo,commandSource:extension.commands.get('fixture-command').sourceInfo===extension.sourceInfo,handlerCalls,handlerIdentity,handlerName:registeredHandler.name,handlerLength:registeredHandler.length,handlersSize:extension.handlers.size});
add('committed-flag-first-default',{flag:runtime.flagValues.get('mode'),registeredDefault:extension.flags.get('mode').default});
add('committed-runtime-queues',{providers:runtime.pendingProviderRegistrations.map(({name,extensionPath})=>({name,extensionPath})),mcp:runtime.mcpServers.list().map(({name,extensionPath})=>({name,extensionPath})),virtual:runtime.pendingVirtualModelRegistrations.map(({definition,extensionPath})=>({provider:definition.provider,id:definition.id,routeName:definition.route.name,routeLength:definition.route.length,extensionPath}))});
add('api-field-order',Object.keys(api));
add('active-command-validation',[thrown(()=>api.registerCommand('',{handler(){}})),thrown(()=>api.registerCommand('missing',{}))]);
add('active-tool-validation',[null,[],()=>undefined,undefined].map(parameters=>thrown(()=>api.registerTool({name:'invalid',parameters}))));
add('active-flag-validation',thrown(()=>api.registerFlag('wrong',{type:'boolean',default:'bad'})));
add('active-provider-required-config',thrown(()=>api.registerProvider('missing')));
add('prebind-action-actual-error',thrown(()=>api.sendMessage({role:'user',content:[]})));
add('prebind-set-model-actual-rejection',await api.setModel({provider:'fixture',id:'unused'}).then(()=>null,error=>({name:error.name,message:error.message})));
const oldConfig=api.getMcpServers()[0].config;oldConfig.args.push('mutated-copy');
add('mcp-list-clone-isolation',api.getMcpServers()[0].config.args);
let failedApi;let failedEvents=0;const marker={reason:'raw-factory-rejection'};
try{
  await loader.loadExtensionFromFactory(async pi=>{
    failedApi=pi;pi.registerFlag('discarded',{type:'boolean',default:true});
    pi.registerProvider('discarded-provider',{baseUrl:'https://example.test'});
    pi.registerMcpServer('discarded-mcp',{command:'never-executed-reference-fixture'});
    pi.events.on('discarded-bus',()=>{failedEvents++});throw marker;
  },cwd,bus,runtime,'<inline:failed>');
  add('raw-rejection-identity',false);
}catch(reason){add('raw-rejection-identity',reason===marker)}
bus.emit('discarded-bus',{});await tick();
add('discarded-pending-state',{flag:runtime.flagValues.has('discarded'),provider:runtime.pendingProviderRegistrations.some(value=>value.name==='discarded-provider'),mcp:runtime.mcpServers.get('discarded-mcp')!==undefined,events:failedEvents});
add('discarded-api-inactive',thrown(()=>failedApi.getFlag('discarded')));
try{await loader.loadExtensionFromFactory(()=>{throw marker},cwd,bus,runtime,'<inline:sync-failure>');add('sync-factory-raw-identity',false)}catch(reason){add('sync-factory-raw-identity',reason===marker)}
add('mcp-ownership-conflict',await loader.loadExtensionFromFactory(pi=>pi.registerMcpServer('fixture-mcp',{command:'unused'}),cwd,bus,runtime,'<inline:other>').then(()=>null,error=>({name:error.name,message:error.message})));
add('mcp-namespace-conflict',await loader.loadExtensionFromFactory(pi=>pi.registerMcpServer('fixture_mcp',{command:'unused'}),cwd,bus,runtime,'<inline:other>').then(()=>null,error=>({name:error.name,message:error.message})));
const ordinaryOrder=[];const ordinary=loader.loadExtensionFromFactory(()=>{ordinaryOrder.push('factory')},cwd,bus,runtime,'<inline:ordinary>');ordinaryOrder.push('after-call');queueMicrotask(()=>ordinaryOrder.push('queued'));await ordinary;ordinaryOrder.push('after-await');
add('ordinary-factory-await-order',ordinaryOrder);
const thenOrder=[];const thenable={get then(){thenOrder.push('then-get');return function(resolve){thenOrder.push(this===thenable?'then-this':'wrong-this');resolve()}}};
const thenPending=loader.loadExtensionFromFactory(()=>{thenOrder.push('factory');return thenable},cwd,bus,runtime,'<inline:thenable>');thenOrder.push('after-call');await thenPending;thenOrder.push('after-await');
add('thenable-factory-await-order',thenOrder);
const commitRuntime=loader.createExtensionRuntime(),commitBus=events.createEventBus();const commitMarker={commit:true};let commitApi,commitEvents=0;
const realRegister=commitRuntime.registerProvider;commitRuntime.registerProvider=function(...args){realRegister(...args);throw commitMarker};
try{await loader.loadExtensionFromFactory(pi=>{commitApi=pi;pi.registerProvider('commit-provider',{baseUrl:'https://example.test'});pi.events.on('commit-event',()=>{commitEvents++})},cwd,commitBus,commitRuntime,'<inline:commit>')}catch(reason){commitBus.emit('commit-event',{});await tick();add('commit-throw-then-discard',{identity:reason===commitMarker,partialProviders:commitRuntime.pendingProviderRegistrations.map(value=>value.name),events:commitEvents,inactive:thrown(()=>commitApi.getFlag('x'))})}
const discardRuntime=loader.createExtensionRuntime(),discardBus=events.createEventBus();const discardMarker={discard:true};const realOn=discardBus.on;
discardBus.on=(...args)=>{const actualUnsubscribe=realOn(...args);return()=>{actualUnsubscribe();throw discardMarker}};
let discardApi;
try{await loader.loadExtensionFromFactory(pi=>{discardApi=pi;pi.events.on('discard-event',()=>undefined);throw marker},cwd,discardBus,discardRuntime,'<inline:discard>')}catch(reason){add('discard-throw-overrides-factory-reason',{identity:reason===discardMarker,inactive:thrown(()=>discardApi.getFlag('x'))})}
const parameterTrace=[];const parameterMarker={parameter:true};
const parameterTool=new Proxy({name:'proxy-tool',parameters:{type:'object'}},{get(target,key,receiver){parameterTrace.push(String(key));if(key==='parameters')throw parameterMarker;return Reflect.get(target,key,receiver)}});
let parameterIdentity=false;try{api.registerTool(parameterTool)}catch(reason){parameterIdentity=reason===parameterMarker}
add('proxy-parameter-raw-getter-reason',{identity:parameterIdentity,trace:parameterTrace});
const flagTrace=[];const flagOptions=new Proxy({type:'boolean',default:true},{get(target,key,receiver){flagTrace.push('get:'+String(key));return Reflect.get(target,key,receiver)},ownKeys(target){flagTrace.push('keys');return Reflect.ownKeys(target)},getOwnPropertyDescriptor(target,key){flagTrace.push('descriptor:'+String(key));return Reflect.getOwnPropertyDescriptor(target,key)}});
api.registerFlag('proxy-flag',flagOptions);add('proxy-flag-read-spread-order',{trace:flagTrace,flag:api.getFlag('proxy-flag')});
const inheritedTrace=[];const inheritedTool=Object.create({get parameters(){inheritedTrace.push('parameters');return {type:'object'}},get name(){inheritedTrace.push('name');return 'inherited-tool'}});
api.registerTool(inheritedTool);add('inherited-tool-getter-order',{trace:inheritedTrace,identity:extension.tools.get('inherited-tool').definition===inheritedTool});
const inheritedFlags=[];const inheritedOptions=Object.create({get type(){inheritedFlags.push('type');return 'boolean'},get default(){inheritedFlags.push('default');return true}});
api.registerFlag('inherited-flag',inheritedOptions);add('inherited-flag-read-spread-order',{trace:inheritedFlags,flag:api.getFlag('inherited-flag'),registeredKeys:Object.keys(extension.flags.get('inherited-flag'))});
runtime.invalidate('fixture-stale');
add('active-api-runtime-invalidated',thrown(()=>api.getMcpServers()));
globalThis.ActualExtensionInitializerRows=rows;

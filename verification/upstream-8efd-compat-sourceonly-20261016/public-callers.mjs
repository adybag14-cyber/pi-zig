// Prepared callers of genuine public modules. No implementation or expected JSON.
export async function observeLiveHostInputs(ai, durable) {
  const {createModels,fauxProvider,fauxAssistantMessage,fauxText,fauxToolCall,Type}=ai;
  const {Harness,MemoryStorage,createRegistry,defineExtension,defineTool}=durable;
  const context={};
  function answering(text){const faux=fauxProvider();faux.setResponses(Array.from({length:10},()=>fauxAssistantMessage([fauxText(text)])));const models=createModels();models.setProvider(faux.provider);return models}
  async function turn(root,content){const settled=await(await root.submit({type:'input',content},context)).wait(context);const entries=await root.entries(context,256,undefined,{});return {status:settled.status,models:entries.items.map(entry=>entry.model)}}
  const rows=[];
  for(const functional of [false,true]){
    let current=answering('first'),settings={stream:{timeoutMs:1000}},modelReads=0,settingReads=0,modelCalls=0,settingCalls=0;
    const receivers=[],options={registry:createRegistry(),get models(){modelReads++;return functional?function(){'use strict';modelCalls++;receivers.push(this===undefined);return current}:current},get settings(){settingReads++;return functional?function(){'use strict';settingCalls++;receivers.push(this===undefined);return settings}:settings}};
    const harness=await Harness.open(new MemoryStorage(),options,context);
    try{
      const root=await harness.root(context,{agent:{model:{provider:'faux',modelId:'faux-1'}}});
      const first=await turn(root,'one');current=answering('second');settings={stream:{timeoutMs:2000}};
      // Replacement option getters must not replace the captured initial values.
      Object.defineProperty(options,'models',{get(){throw Error('late models option read')}});
      Object.defineProperty(options,'settings',{get(){throw Error('late settings option read')}});
      const second=await turn(root,'two');rows.push({kind:'captured-options',functional,first,second,modelReads,settingReads,modelCalls,settingCalls,receivers});
    }finally{await harness.close(context)}
  }
  {
    const first=createModels(),second=createModels(),faux=fauxProvider();
    faux.setResponses([fauxAssistantMessage([fauxToolCall('probe',{},{id:'call-1'})],{stopReason:'toolUse'}),fauxAssistantMessage([fauxText('done')])]);first.setProvider(faux.provider);second.setProvider(faux.provider);let current=first;
    const observations=[],registry=createRegistry(),environment={fixture:'owned-env-input'};
    registry.install(defineExtension({name:'probe',tools:[defineTool({name:'probe',description:'Observe current public host inputs',parameters:Type.Object({}),async execute(_args,api){const a=api.models;current=second;const b=api.models;const md=Object.getOwnPropertyDescriptor(api,'models'),ed=Object.getOwnPropertyDescriptor(api,'env');observations.push({firstSame:a===first,secondSame:b===second,envSame:api.env===environment,modelsGetter:typeof md?.get,envGetter:typeof ed?.get,modelsGetterName:md?.get?.name,envGetterName:ed?.get?.name,keys:Object.keys(api)});return{output:[]}}})]}));
    const harness=await Harness.open(new MemoryStorage(),{models:()=>current,registry,env:()=>environment},context);
    try{const root=await harness.root(context,{agent:{model:{provider:'faux',modelId:'faux-1'}}});rows.push({kind:'tool-live-access',turn:await turn(root,'go'),observations})}finally{await harness.close(context)}
  }
  return rows;
}

// Genuine source resolver with caller-supplied runtime inventory. The generated
// catalog stays untouched. A supplied default is an explicit custom runtime
// input, never a fabricated catalog row or authority assertion.
export async function observeNvidiaDefault(resolver, actualModels, suppliedDefault) {
  const providerModels=actualModels.filter(model=>model.provider==='nvidia');
  const wanted='nvidia/nemotron-3.5-super-vl-120b-a12b',rows=[];
  for(const available of [providerModels.slice(0,2),...(suppliedDefault?[providerModels.slice(0,2).concat(suppliedDefault)]:[])]){
    const trace=[],runtime={getAvailableSnapshot(){trace.push('available');return available},getModel(provider,id){trace.push(['model',provider,id]);return available.find(model=>model.provider===provider&&model.id===id)},hasConfiguredAuth(){return true}};
    const result=await resolver.findInitialModel({modelRuntime:runtime,scopedModels:[],isContinuing:false});
    rows.push({available:available.map(model=>[model.provider,model.id]),selected:result.model&&[result.model.provider,result.model.id],trace});
  }
  return{exportedDefault:resolver.defaultModelPerProvider.nvidia,exactCatalogHasDefault:providerModels.some(model=>model.id===wanted),rows};
}

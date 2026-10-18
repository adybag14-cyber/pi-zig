// The namespace under observation is the actual c268 Source module or its native
// owner. Guest fetch callbacks are controlled inputs to the real management
// retry helper; these observations do not claim network transport certification.
function insist(condition, message) { if (!condition) throw Error(message); }
function equal(actual, expected, label) {
  insist(JSON.stringify(actual) === JSON.stringify(expected), label + ': ' + JSON.stringify(actual));
}
function baseProvider(id = 'owned/provider') {
  return { id, getModels() { return [{id:'builtin',provider:id}, {id:'shared',provider:id,source:'builtin'}]; } };
}
function ids(models) { return models.map(m => [m.type ?? 'chat', m.id, m.source ?? null]); }
async function withFetch(callback, body) {
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, 'fetch');
  try { globalThis.fetch = callback; return await body(); }
  finally { if (descriptor) Object.defineProperty(globalThis, 'fetch', descriptor); else delete globalThis.fetch; }
}
export async function observeRemoteOffline(api) {
  const rows = [];
  const provider = baseProvider();
  const restored = [{id:'shared',provider:provider.id,source:'remote'}, {id:'image',type:'image',provider:provider.id}, {id:'foreign',provider:'elsewhere'}];
  const wrapped = api.withRemoteCatalog(provider, undefined, 10);
  let fetched = 0;
  await withFetch(() => { fetched++; throw Error('offline fetched'); }, async () => {
    const log = [];
    const context = {stored:{models:restored,lastModified:20}, get allowNetwork(){log.push('network');return false}, get signal(){throw Error('offline signal read')}, publish(record){log.push('publish');record.update();return true}};
    const pending = wrapped.refreshModels(context);
    log.push('caller');
    equal(log, ['publish','caller'], 'restoration must Await publication');
    await pending;
    equal(log, ['publish','caller','network'], 'offline gate continuation');
    equal(ids(wrapped.getModels()), [['chat','builtin',null],['chat','shared','remote']], 'remote chat merge');
    equal(ids(wrapped.getAllModels()), [['chat','builtin',null],['chat','shared','remote'],['image','image',null]], 'all model types merge');
    rows.push(['offline',log,ids(wrapped.getModels()),ids(wrapped.getAllModels())]);
    const suppressed = api.withRemoteCatalog(provider);
    await suppressed.refreshModels({stored:{models:restored},publish(record){record.update();return false},get allowNetwork(){throw Error('false publish continued')}});
    rows.push(['publication-false',ids(suppressed.getAllModels())]);
    const old = api.withRemoteCatalog(provider, undefined, 20);
    await old.refreshModels({stored:{models:restored,lastModified:20},publish(record){record.update();return true},allowNetwork:false});
    equal(ids(old.getAllModels()), [['chat','builtin',null],['chat','shared','builtin']], 'equal generated time excludes overlay');
    const fresh = api.withRemoteCatalog(provider);
    await fresh.refreshModels({stored:{models:restored,checkedAt:Date.now(),lastModified:20},publish(record){record.update();return true},allowNetwork:true,signal:new AbortController().signal});
    rows.push(['fresh-window',ids(fresh.getAllModels())]);
  });
  insist(fetched === 0, 'offline/fresh request count');
  return rows;
}
export async function observeRemoteNetwork(api, userAgent) {
  const rows = [];
  for (const status of [200,304,404,501,418]) {
    const provider = baseProvider();
    const log = [], calls = [];
    const stored = {models:[{id:'stored',provider:provider.id}],lastModified:1,checkedAt:0,etag:'owned-validator'};
    let invocation = 0;
    const response = {
      get status(){log.push('status');return status},
      get ok(){log.push('ok');return status === 200},
      get headers(){log.push('headers');return {get(name){log.push('header:'+name);return name === 'last-modified' ? 'Thu, 01 Jan 1970 00:00:01 GMT' : 'owned-etag'}}},
      json(){log.push('json');return {then(resolve){log.push('json-then');resolve({models:[{id:'new',provider:'ignored'}, {id:'pic',type:'image'}, {id:'unsupported',type:'audio'}, null, {missing:'id'}]})}}}
    };
    const wrapped = api.withRemoteCatalog(provider, 'https://catalog.invalid/base', 0);
    let persisted, caught;
    await withFetch(function(input, init){
      insist(this === undefined, 'fetch receiver');
      invocation++;
      calls.push([String(input),init.headers.accept,init.headers['User-Agent'],init.headers['if-none-match'],init.signal instanceof AbortSignal]);
      return response;
    }, async () => {
      try {
        await wrapped.refreshModels({stored,force:true,allowNetwork:true,signal:new AbortController().signal,
          publish(record){log.push(record.persist?'persist':'restore');if(record.persist)persisted=record.persist;record.update?.();return true}});
      } catch(error) { caught=error; }
    });
    insist(invocation === 1, 'nonretry status uses one actual fetch');
    equal(calls[0].slice(0,4), ['https://catalog.invalid/api/models/providers/owned%2Fprovider?types=chat%2Cimage%2Cclassifier','application/json',userAgent,'owned-validator'], 'actual catalog request');
    insist(calls[0][4], 'real composed abort signal');
    insist(Number.isFinite(persisted.checkedAt), 'actual Date.now checkedAt');
    if(status===200){
      insist(caught===undefined, 'successful response');
      equal(persisted.models.map(m=>[m.id,m.provider,m.type??'chat']), [['new',provider.id,'chat'],['pic',provider.id,'image']], 'actual parse and provider binding');
      insist(persisted.lastModified===1000 && persisted.etag==='owned-etag', 'last modified and etag');
      equal(log.filter(x=>x.startsWith('header:')||x==='json'||x==='json-then'||x==='persist'), ['header:last-modified','json','json-then','header:etag','persist'], 'actual readCatalog Await');
    } else if(status===304) {
      insist(persisted.models===stored.models && persisted.etag===stored.etag && caught===undefined, '304 retained stored identities');
    } else if(status===404||status===501) {
      insist(persisted.models===stored.models && persisted.etag===undefined && persisted.lastModified===0 && caught===undefined, 'missing catalog persistence');
    } else {
      insist(caught instanceof Error && caught.message==='Model catalog request failed for owned/provider: 418', 'post publication request error');
      insist(persisted.models===stored.models && persisted.etag===stored.etag, 'transient validator retained');
      insist(log.indexOf('persist') < log.lastIndexOf('status'), 'throw status evaluated after publication');
    }
    rows.push([status,log,ids(wrapped.getAllModels()),!!caught]);
  }
  let attempts=0,cancelled=0;
  await withFetch(() => ++attempts===1 ? {status:503,body:{cancel(){cancelled++;return undefined}}} : {status:404}, async () => {
    const wrapped=api.withRemoteCatalog(baseProvider());
    await wrapped.refreshModels({force:true,allowNetwork:true,signal:new AbortController().signal,publish(record){record.update?.();return true}});
  });
  insist(attempts===2 && cancelled===1, 'actual management retry retained');
  rows.push(['retry',attempts,cancelled]);
  return rows;
}
export async function observePersonalizedCatalog(api) {
  const rows=[],provider=baseProvider(),log=[];
  const personal=[{id:'personal',provider:provider.id},{id:'personal-image',type:'image',provider:provider.id}];
  let context;
  const wrapped=api.withPersonalizedCatalog(provider, async (models, supplied) => {
    insist(supplied===context, 'personalize context identity');
    log.push(['personalize',ids(models)]);return personal;
  });
  await withFetch(() => ({status:404}), async () => {
    context={stored:{models:[{id:'previous',provider:provider.id}]},force:false,allowNetwork:true,signal:new AbortController().signal,
      publish(record){log.push(record.persist?'persist':'restore');record.update?.();if(record.persist)insist(record.persist.models===personal,'personal result identity');return true}};
    await wrapped.refreshModels(context);
  });
  equal(ids(wrapped.getModels()), [['chat','personal',null]], 'personal chat projection');
  equal(ids(wrapped.getAllModels()), [['chat','personal',null],['image','personal-image',null]], 'personal full replacement');
  equal(log, ['restore',['personalize',[['chat','builtin',null],['chat','shared','builtin']]],'persist'], 'personal absent catalog order');
  rows.push(['missing',log]);
  const fallback=api.withPersonalizedCatalog(provider,async()=>{throw Error('offline personalize')});
  await fallback.refreshModels({stored:{models:[]},allowNetwork:false,publish(record){record.update();return true}});
  equal(ids(fallback.getAllModels()), [['chat','builtin',null],['chat','shared','builtin']], 'empty personal fallback');
  const stopped=api.withPersonalizedCatalog(provider,async()=>{throw Error('aborted personalize')});
  const controller=new AbortController();
  await withFetch(() => {controller.abort();return {get status(){throw Error('aborted response inspected')}}}, async () => {
    await stopped.refreshModels({allowNetwork:true,signal:controller.signal,publish(record){record.update?.();return true}});
  });
  rows.push(['empty-and-aborted']);
  return rows;
}
export async function observeRemoteConcurrent(api) {
  const provider=baseProvider(),wrapped=api.withRemoteCatalog(provider);
  const releases=[],log=[];
  function context(id){return {stored:{models:[{id,provider:provider.id}]},allowNetwork:false,publish(record){log.push(id);record.update();return new Promise(resolve=>releases.push(resolve))}}}
  const first=wrapped.refreshModels(context('first')),second=wrapped.refreshModels(context('second'));
  equal(log,['first','second'],'both Source prefixes execute immediately');
  releases[1](true);await second;releases[0](false);await first;
  insist(wrapped.getAllModels().some(m=>m.id==='second'), 'independent continuation state');
  const reason={owned:'publish thenable'};
  let caught;
  try{await wrapped.refreshModels({stored:undefined,publish(){return {get then(){throw reason}}}})}catch(error){caught=error}
  insist(caught===reason,'thenable rejection identity');
  return [log,ids(wrapped.getAllModels()),caught===reason];
}
export async function observeRemoteSpreadAndIteration(api) {
  const log=[],symbol=Symbol('public'),target={id:'provider',getModels(){return []},[symbol]:'symbol'};
  Object.defineProperty(target,'hidden',{value:1});
  const provider=new Proxy(target,{
    ownKeys(value){log.push('keys');return Reflect.ownKeys(value)},
    getOwnPropertyDescriptor(value,key){log.push('descriptor:'+String(key));return Reflect.getOwnPropertyDescriptor(value,key)},
    get(value,key,receiver){log.push('get:'+String(key));return Reflect.get(value,key,receiver)}
  });
  const wrapped=api.withRemoteCatalog(provider);
  insist(wrapped[symbol]==='symbol' && !('hidden'in wrapped),'Source spread symbols and nonenumerable property');
  equal(log,['keys','descriptor:id','get:id','descriptor:getModels','get:getModels','descriptor:hidden','descriptor:'+String(symbol),'get:'+String(symbol)],'spread descriptor/get order');
  const original=Array.prototype[Symbol.iterator],reason={owned:'merge body'},closeReason={owned:'close'};
  let closes=0;
  try{
    Array.prototype[Symbol.iterator]=function(){
      if(this.length===1 && this[0]?.id==='bad'){
        let done=false;return{next(){if(done)return{done:true};done=true;return{done:false,value:{get type(){throw reason},id:'bad'}}},return(){closes++;throw closeReason}}
      }
      return original.call(this);
    };
    let caught;
    try{api.withRemoteCatalog({id:'provider',getModels(){return[{id:'bad'}]}}).getModels()}catch(error){caught=error}
    insist(caught===reason && closes===1,'for-of ordinary throw wins IteratorClose');
  }finally{Array.prototype[Symbol.iterator]=original}
  return [log,closes];
}


// The fetch retry owner sees the ordinary status before the Source continuation
// resumes. Its next context.signal getter activates sole status-result carriers,
// so this observation targets the exact RemoteCatalog comparison expressions.
export async function observeRemoteStatusRetirement(api, hooks, personal) {
  let fetched = false, inspect = false, reads = 0;
  const expected = personal ? 2 : 3;
  const signal = new AbortController().signal;
  globalThis.remoteStatusReads = 0;
  const response = {
    get status() {
      if (!inspect) return 200;
      if (reads && hooks.count(reads - 1) !== 1) throw Error('prior status result retained');
      globalThis.remoteStatusReads = ++reads;
      return hooks.make(reads - 1);
    },
    get ok() {
      hooks.visit(2);
      insist(reads === expected, 'all live Source status comparisons');
      for (let slot = 0; slot < reads; slot++) insist(hooks.count(slot) === 1, 'status result retained before ok');
      return true;
    },
    headers: { get() { return null; } },
    json() { return []; }
  };
  const provider = {id:'actual-status-retirement',getModels(){return[]}};
  const wrapped = personal ? api.withPersonalizedCatalog(provider, models => models) : api.withRemoteCatalog(provider);
  await withFetch(() => { fetched = true; return response; }, async () => {
    await wrapped.refreshModels({
      force:true,allowNetwork:true,
      get signal(){ if (fetched) inspect = true; return signal; },
      publish(record){ record.update?.(); return true; }
    });
  });
  insist(reads === expected, 'status retirement observer must execute');
  return reads;
}

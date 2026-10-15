// Caller inputs only. No Source method/prototype/import body is replaced.
export async function observe({ModelRuntime,CredentialSynchronizationError,operationSignal,raceWithAbortSignal}) {
  const tick=async()=>{for(let i=0;i<12;i++)await Promise.resolve()};
  const rows=[];
  const descriptor=fn=>({name:fn.name,length:fn.length,async:Object.getPrototypeOf(fn)===Object.getPrototypeOf(async()=>{})});
  rows.push({case:'prototype',constructor:descriptor(ModelRuntime),methods:Object.getOwnPropertyNames(ModelRuntime.prototype).map(name=>{const d=Object.getOwnPropertyDescriptor(ModelRuntime.prototype,name);return {key:name,enumerable:d.enumerable,configurable:d.configurable,writable:d.writable,...descriptor(d.value)}}),errorConstructor:descriptor(CredentialSynchronizationError)});
  rows.push({case:'abort-metadata',functions:[operationSignal,raceWithAbortSignal].map(fn=>({...descriptor(fn),ownPrototype:Object.hasOwn(fn,'prototype')}))});
  let liveModels=[{id:'first',provider:'caller',api:'caller',type:'chat',input:['text'],reasoning:false,cost:{input:0,output:0,cacheRead:0,cacheWrite:0},contextWindow:4096,maxTokens:100}];
  const commits=[],runtimeKeys=new Map();
  const credentials={read:async()=>undefined,list:async()=>[],modify:async()=>{},hasRuntimeApiKey:id=>runtimeKeys.has(id),setRuntimeApiKey(id,key){runtimeKeys.set(id,key);commits.push([id,key])},removeRuntimeApiKey(id){runtimeKeys.delete(id);commits.push([id,'remove'])}};
  let configured;
  const config={getProviderIds(){return[]},getProvider(){return configured},getError(){return undefined}};
  const provider={id:'caller',auth:{apiKey:{resolve:async()=>({auth:{apiKey:'caller-fixture'},source:'caller'})}},getModels(){return liveModels},getAllModels(){return liveModels},stream(){throw Error('not requested')},streamSimple(){throw Error('not requested')}};
  const instance=new ModelRuntime(credentials,config,undefined,undefined,[provider],true);
  rows.push({case:'construction',keys:Object.keys(instance),instanceof:instance instanceof ModelRuntime,defaultProviderIdentity:instance.defaultBuiltins.get('caller')===provider,credentialsIdentity:instance.credentials===credentials,configIdentity:instance.config===config,snapshotKeys:Object.keys(instance.snapshot)});
  liveModels=[{...liveModels[0],id:'second'}];
  rows.push({case:'live-models',ids:instance.getModels().map(model=>model.id),providerIdentity:instance.getProvider('caller')===provider});
  // Controlled collaborator methods expose ModelRuntime's own orchestration.
  // The actual Models collection is constructed above; production has no mocks.
  const resolution={auth:{apiKey:'caller-key',baseUrl:'https://caller.invalid',headers:{'X-Mode':'resolved',Keep:'yes'}},env:{BASE:'one'},extra:true};
  instance.models.getAuth=async()=>resolution;
  configured={headers:{'x-mode':'configured'}};
  const auth=await instance.getAuth(liveModels[0],{env:{OVERRIDE:'two'}});
  let transformReads=0,transformed;
  const symbol=Symbol('caller-options');
  const options={apiKey:'request-key',headers:{KEEP:'request'},env:{REQUEST:'three'},[symbol]:'retained',get transformHeaders(){transformReads++;return async headers=>(transformed={...headers,Transform:'yes'})}};
  const prepared=await instance.prepareRequest(liveModels[0],options);
  rows.push({case:'request',authHeaders:auth.auth.headers,authEnv:auth.env,modelCloned:prepared.model!==liveModels[0],baseUrl:prepared.model.baseUrl,headers:prepared.options.headers,apiKey:prepared.options.apiKey,env:prepared.options.env,transformReads,symbolRetained:prepared.options[symbol],transformOmitted:!('transformHeaders'in prepared.options),transformIdentity:prepared.options.headers===transformed});
  configured=undefined;
  let fullRelease,providerRelease;
  const first={...liveModels[0],id:'first'},second={...liveModels[0],id:'second'};
  instance.models.getProviders=()=>[provider];instance.models.getModels=()=>[first,second];
  instance.models.getAvailable=id=>new Promise(resolve=>{if(id===undefined)fullRelease=resolve;else providerRelease=resolve});
  instance.models.checkAuth=async()=>({type:'api_key',source:'caller'});
  const full=instance.queueAvailabilityRefresh();const scoped=instance.refreshProviderAvailability('caller',operationSignal());
  providerRelease([second]);await scoped;fullRelease([first]);await full;
  rows.push({case:'stale-availability',ids:instance.getAvailableSnapshot().map(model=>model.id),configured:instance.hasConfiguredAuth('caller'),stored:instance.snapshot.storedProviders.has('caller'),auth:instance.snapshot.auth.get('caller')});
  let finishFirst;instance.models.getAvailable=async()=>[second];instance.models.refresh=()=>new Promise(resolve=>{finishFirst=()=>resolve({aborted:false,errors:new Map()})});
  const firstKey=instance.setRuntimeApiKey('caller','first-key');await tick();
  const controller=new AbortController(),reason={identity:'queued-abort'};const secondKey=instance.setRuntimeApiKey('caller','second-key',{signal:controller.signal});controller.abort(reason);
  let abortIdentity=false;try{await secondKey}catch(error){abortIdentity=error===reason}
  finishFirst();await firstKey;await tick();
  rows.push({case:'credential-queue',commits:[...commits],abortIdentity,remainingQueues:instance.credentialOperations.size});
  const original=Error('caller-refresh-failure');instance.models.refresh=async()=>({aborted:false,errors:new Map([['caller',original]])});
  let synchronization;try{await instance.setRuntimeApiKey('caller','committed-key')}catch(error){synchronization=error}
  rows.push({case:'committed-error',classIdentity:synchronization instanceof CredentialSynchronizationError,causeIdentity:synchronization?.cause===original,name:synchronization?.name,message:synchronization?.message,providerId:synchronization?.providerId,operation:synchronization?.operation,credential:synchronization?.credential,keys:Object.keys(synchronization),committed:runtimeKeys.get('caller')});
  let removed=0,listener;const fakeSignal={aborted:false,addEventListener(type,callback){listener=callback},removeEventListener(type,callback){if(callback===listener)removed++}};
  const result={retained:true};const raced=await raceWithAbortSignal(Promise.resolve(result),fakeSignal);listener();
  let reasonReads=0;const earlier={},later={},liveReason={aborted:true,get reason(){return ++reasonReads===1?earlier:later}};let rejection;
  try{await raceWithAbortSignal(Promise.resolve(),liveReason)}catch(error){rejection=error}
  rows.push({case:'abort-helper',resultIdentity:raced===result,removed,optionalSignal:operationSignal().aborted,reasonReads,liveReasonIdentity:rejection===later});
  return {sourceHead:'4954d760504c11df9b2cbdc040346107b6a8153d',rows};
}

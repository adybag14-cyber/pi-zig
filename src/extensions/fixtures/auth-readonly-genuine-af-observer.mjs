import fs from 'node:fs';
import path from 'node:path';
function assert(value,label){if(!value)throw Error(label)}
function held(){let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b});return {promise,resolve,reject}}
export async function observeReadonly(ReadOnlyAuthStorage,readStoredCredential,root){
  const rows=[];
  rows.push({kind:'shapes',constructor:{name:ReadOnlyAuthStorage.name,length:ReadOnlyAuthStorage.length},methods:['load','read','list','modify','delete'].map(name=>{
    const descriptor=Object.getOwnPropertyDescriptor(ReadOnlyAuthStorage.prototype,name),fn=descriptor.value;
    return {name:fn.name,length:fn.length,tag:Object.prototype.toString.call(fn),ownPrototype:Object.hasOwn(fn,'prototype'),enumerable:descriptor.enumerable};
  })});
  const file=path.join(root,'actual-readonly.json');
  fs.writeFileSync(file,JSON.stringify({oauth:{type:'oauth',access:'owned-access',refresh:'owned-refresh',expires:123,extra:{kept:true}},literal:{type:'api_key',key:'owned-literal'},command:{type:'api_key',key:'!must-not-execute'},templated:{type:'api_key',key:'${READONLY_OWNED_VALUE}',env:{READONLY_OWNED_VALUE:'owned-env'}}}),'utf8');
  const store=new ReadOnlyAuthStorage(file);
  const credential=await store.read('oauth');credential.extra.kept=false;
  const again=await store.read('oauth');assert(again.extra.kept,'actual structuredClone isolation');
  const literal=await store.read('literal'),command=await store.read('command'),templated=await store.read('templated');
  assert(literal.key==='owned-literal'&&command.key==='!must-not-execute'&&templated.key==='owned-env','actual config-value bindings');
  const list=await store.list();assert(list.map(row=>row.providerId).join(',')==='oauth,literal,command,templated','actual entries/map order');
  rows.push({kind:'actual-file',credential:again,literal,command,templated,list});
  fs.writeFileSync(file,'{}','utf8');assert((await store.read('oauth')).access==='owned-access','snapshot remains cached');
  const missing=new ReadOnlyAuthStorage(path.join(root,'missing-readonly.json'));
  assert(await missing.read('absent')===undefined,'ENOENT becomes cached empty');
  rows.push({kind:'cache-and-missing',snapshot:(await store.read('oauth')).access,missing:await missing.list()});
  for(const method of ['modify','delete']){
    let synchronous=false,pending,caught,entered=0;
    try{pending=method==='modify'?store.modify('oauth',async()=>{entered++;return undefined}):store.delete('oauth')}catch{synchronous=true}
    try{await pending}catch(reason){caught=reason}
    assert(!synchronous&&caught?.message==='Read-only credential storage cannot modify auth.json'&&entered===0,'genuine async mutation rejection');
    rows.push({kind:method,synchronous,name:caught.name,message:caught.message,entered});
  }
  const stop={identity:'readonly-signal'};let checks=0,caught;
  try{await store.read('oauth',{signal:{throwIfAborted(){if(++checks===2)throw stop}}})}catch(reason){caught=reason}
  assert(caught===stop&&checks===2,'second actual signal check/raw reason');rows.push({kind:'signal',checks,same:caught===stop});
  const clone=globalThis.structuredClone,deferred=held();
  globalThis.structuredClone=function(value){assert(value.type==='oauth','actual credential passed');return deferred.promise};
  let settled=false;const adopted=store.read('oauth').then(value=>{settled=true;return value});
  await Promise.resolve();assert(!settled,'real async return adoption');deferred.resolve('owned-adopted');
  assert(await adopted==='owned-adopted','adopted return');globalThis.structuredClone=clone;
  rows.push({kind:'return-adoption',settled});
  const invalid=path.join(root,'invalid-readonly.json');fs.writeFileSync(invalid,'{"bad":{"type":"unknown"}}','utf8');
  try{await new ReadOnlyAuthStorage(invalid).list()}catch(reason){caught=reason}
  assert(caught.message==='Invalid auth.json credential for provider "bad"','validation is outside read-error wrapping');
  rows.push({kind:'invalid-credential',name:caught.name,message:caught.message});
  const malformed=path.join(root,'malformed-readonly.json');fs.writeFileSync(malformed,'{','utf8');
  try{await new ReadOnlyAuthStorage(malformed).read('x')}catch(reason){caught=reason}
  assert(caught.message.startsWith('Failed to read auth.json: '),'parse failure wrapped');
  rows.push({kind:'malformed',name:caught.name,message:caught.message}); // Full VM message retained, not normalized.
  const raw=readStoredCredential('bad',invalid);
  assert(raw?.type==='unknown'&&readStoredCredential('x',malformed)===undefined,'ordinary one-off read does not run store validation');
  rows.push({kind:'ordinary-one-off',name:readStoredCredential.name,length:readStoredCredential.length,tag:Object.prototype.toString.call(readStoredCredential),raw,malformed:readStoredCredential('x',malformed)===undefined});
  const originalEnv=Object.getOwnPropertyDescriptor(process,'env'),defaultReason={identity:'default-agent-dir'};
  const ownedEnv=Object.create(null);Object.defineProperty(ownedEnv,'PI_CODING_AGENT_DIR',{get(){throw defaultReason}});
  Object.defineProperty(process,'env',{...originalEnv,value:ownedEnv});
  let defaultCaught;try{readStoredCredential('oauth')}catch(reason){defaultCaught=reason}
  Object.defineProperty(process,'env',originalEnv);
  assert(defaultCaught===defaultReason,'default argument must precede best-effort try');
  rows.push({kind:'default-outside-try',same:defaultCaught===defaultReason});
  return rows;
}
export async function verifyReadonlyData(ReadOnlyAuthStorage,root,makeData){
  const file=path.join(root,'readonly-data.json');fs.writeFileSync(file,'{"oauth":{"type":"oauth","access":"a","refresh":"r","expires":1}}','utf8');
  const store=new ReadOnlyAuthStorage(file),clone=globalThis.structuredClone,data=makeData();
  globalThis.structuredClone=function(){return Promise.reject(data)};
  let caught;try{await store.read('oauth')}catch(reason){caught=reason}
  assert(caught===data,'rejected return-adoption DATA identity');
  globalThis.structuredClone=function(){return data};assert(await store.read('oauth')===data,'fulfilled returned DATA identity');
  globalThis.structuredClone=clone;
  return {sameRejectedData:caught===data,sameReturnedData:true};
}

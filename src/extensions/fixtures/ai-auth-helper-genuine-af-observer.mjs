// Shared caller for the actual helper factories. No model registry, completed
// storage surrogate, replacement Promise constructor or fake import graph.
export async function observeAuthHelpers(api, context) {
  const assert=(ok,message)=>{if(!ok)throw Error(message)};
  const rows=[];
  const signal={throwIfAborted(){}};
  const auth=api.envApiKeyAuth('Owned key',['FIRST','SECOND']);
  let release,log=[];
  const promptPromise=new Promise(resolve=>{release=resolve});
  const interaction={signal,prompt(options){log.push(options.message);assert(this===interaction,'prompt receiver');return promptPromise}};
  const login=auth.login.call({decoy:true},interaction);
  assert(login!==promptPromise,'genuine outer Promise identity');
  assert(log.join(',')==='Enter Owned key','prompt must run before return');
  let finished=false;login.then(()=>{finished=true});await Promise.resolve();
  assert(!finished,'login Await must hold');release('owned-key');
  const credential=await login;assert(credential.key==='owned-key','prompt result');
  rows.push({case:'login-held',outerDistinct:login!==promptPromise,credential,log});

  const envIdentity={OWNED:'yes'},reads=[];
  const stored=await auth.resolve({get ctx(){reads.push('ctx');return{}},get credential(){reads.push('credential');return{get key(){reads.push('key');return'key'},get env(){reads.push('env');return envIdentity}}},get signal(){reads.push('signal');return signal}});
  assert(stored.env===envIdentity,'stored env identity');
  assert(reads.join(',')==='ctx,credential,signal,key,key,env','Source destructuring and credential double reads');
  rows.push({case:'stored-reads',reads,sameEnv:stored.env===envIdentity});

  let closed=0,envCalls=[];
  const iterable={[Symbol.iterator](){let n=0;return{next(){return n++<2?{value:n===1?'FIRST':'SECOND',done:false}:{done:true}},return(){closed++;return{done:true}}}}};
  const fromEnv=api.envApiKeyAuth('Owned iterator',iterable);
  const ctx={env(name){assert(this===ctx,'ctx.env receiver');envCalls.push(name);return Promise.resolve(name==='SECOND'?'second-key':undefined)}};
  const resolved=await fromEnv.resolve({ctx,signal});
  assert(resolved.source==='SECOND'&&closed===1,'successful return closes iterator');
  rows.push({case:'env-order',envCalls,closed,result:resolved});

  const reason={owned:'rejection'},closeReason={owned:'close'};
  const rejecting=api.envApiKeyAuth('Owned rejected',{[Symbol.iterator](){return{next(){return{value:'ONLY',done:false}},return(){throw closeReason}}}});
  let caught;try{await rejecting.resolve({ctx:{env(){return Promise.reject(reason)}},signal})}catch(error){caught=error}
  assert(caught===reason,'Await rejection preserves original over IteratorClose');
  rows.push({case:'rejected-close',sameReason:caught===reason});
  let stepClose=0;
  const broken=api.envApiKeyAuth('Owned step',{[Symbol.iterator](){return{next(){return{get value(){throw reason},done:false}},return(){stepClose++;return{}}}}});
  try{await broken.resolve({ctx,signal})}catch(error){assert(error===reason,'IteratorValue reason')}
  assert(stepClose===0,'IteratorValue throw does not close');rows.push({case:'step-does-not-close',stepClose});

  let loads=0,loadedRelease,thenGets=0,delegation=[];
  const loadedPromise=new Promise(resolve=>{loadedRelease=resolve});
  Object.defineProperty(loadedPromise,'then',{get(){thenGets++;throw reason}});
  const lazy=api.lazyOAuth({name:'Owned flow',load(){loads++;return loadedPromise}});
  const input={access:'owned'},options={owned:'options'};
  const first=lazy.login(input,options),second=lazy.refresh(input,signal),third=lazy.toAuth(input);
  const delegate={login(a,b){assert(this===delegate&&a===input&&b===options,'login delegation identity');delegation.push('login');return{method:'login'}},refresh(a,b){assert(this===delegate&&a===input&&b===signal,'refresh delegation identity');delegation.push('refresh');return{method:'refresh'}},toAuth(a){assert(this===delegate&&a===input,'toAuth delegation identity');delegation.push('toAuth');return input}};
  loadedRelease(delegate);
  const values=await Promise.all([first,second,third]);
  assert(loads===1&&thenGets===0&&values[2]===input,'real intrinsic Await and cached load identity');
  rows.push({case:'lazy-real-await',loads,thenGets,delegation,sameCredential:values[2]===input});

  let retry=0;
  const retrying=api.lazyOAuth({name:'Owned retry',load(){retry++;throw reason}});
  for(let n=0;n<2;n++)try{await retrying.toAuth(input)}catch(error){assert(error===reason,'sync load throw identity')}
  assert(retry===2,'sync throw must not populate cache');rows.push({case:'lazy-sync-retry',retry});

  let adoptedGets=0;
  const returnedPromise=Promise.resolve(input);
  Object.defineProperty(returnedPromise,'then',{get(){adoptedGets++;return Promise.prototype.then}});
  const tail=api.lazyOAuth({name:'Owned return',load(){return Promise.resolve({toAuth(){return returnedPromise}})}});
  const adopted=await tail.toAuth(input);
  assert(adopted===input&&adoptedGets===1,'tail return adopts once, adds no second Await');
  rows.push({case:'lazy-return-adoption',adoptedGets,sameCredential:adopted===input});

  if(context){const value=await context.env('PI_AUTH_HELPER_OWNED');rows.push({case:'context-env',value})}
  return rows;
}

// Real Graph0 route only. Caller supplies the actual physical Source context
// URL, a genuine queued native context factory, and a real owned existing path.
export async function observeAuthContext(context, existingPath, missingPath) {
  const exists=await context.fileExists(existingPath);
  const missing=await context.fileExists(missingPath);
  const invalid=await context.fileExists(undefined);
  const badTilde=await context.fileExists('~\0invalid');
  if(!exists||missing||invalid||badTilde)throw Error('real queued fs/os context behavior');
  return {exists,missing,invalid,badTilde};
}

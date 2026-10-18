// Shared caller for actual providers/anthropic.ts anthropicApiKeyAuth.
// Controlled AuthContext/interaction parameters are the real factory API.
export async function observeAnthropicApiKey(auth) {
  const assert=(ok,message)=>{if(!ok)throw Error(message)};
  const rows=[];
  let release,signals=0,aborts=0,thenGets=0;
  const promptPromise=new Promise(resolve=>{release=resolve});
  Object.defineProperty(promptPromise,'then',{get(){thenGets++;throw Error('Await must use intrinsic Promise')}});
  const interaction={get signal(){signals++;return{throwIfAborted(){aborts++}}},prompt(options){assert(this===interaction,'prompt receiver');assert(options.type==='secret'&&options.message==='Enter Anthropic API key','prompt options');return promptPromise}};
  const pending=auth.login.call({decoy:true},interaction);
  assert(signals===1&&aborts===1&&pending!==promptPromise,'prompt synchronous prefix and outer identity');
  release('owned-login-key');const credential=await pending;
  assert(credential.type==='api_key'&&credential.key==='owned-login-key'&&signals===2&&aborts===2&&thenGets===0,'one real login Await');
  rows.push({case:'login',signals,aborts,thenGets,credential});
  const reads=[],envIdentity={owned:'env'};
  const stored=await auth.resolve({get ctx(){reads.push('ctx');return{env(){throw Error('stored must not read env')}}},get credential(){reads.push('credential');return{get key(){reads.push('key');return'owned-stored'},get env(){reads.push('env');return envIdentity}}},get signal(){reads.push('signal');return{throwIfAborted(){reads.push('abort')}}}});
  assert(reads.join(',')==='ctx,credential,signal,abort,key,key,env'&&stored.env===envIdentity,'destructure and key double read');
  rows.push({case:'stored',reads,sameEnv:stored.env===envIdentity});
  const names=['ANTHROPIC_AUTH_TOKEN','ANTHROPIC_OAUTH_TOKEN','ANTHROPIC_API_KEY','ANTHROPIC_FEDERATION_RULE_ID','ANTHROPIC_ORGANIZATION_ID','ANTHROPIC_IDENTITY_TOKEN_FILE','ANTHROPIC_SERVICE_ACCOUNT_ID','ANTHROPIC_WORKSPACE_ID'];
  for(const stop of [0,1,2,3,4,5,8]) {
    const trace=[];let calls=0;
    const signal={throwIfAborted(){trace.push('abort')}};
    const ctx={env(name){assert(this===ctx,'env receiver');trace.push(name);const index=names.indexOf(name);calls++;return Promise.resolve(stop<3?(index===stop?'owned-'+name:undefined):(index>=3&&index<stop?'owned-'+name:undefined))}};
    const value=await auth.resolve({ctx,signal});
    const expected=stop<3?stop+1:stop===8?8:stop+1;
    assert(calls===expected&&trace.length===1+2*calls,'exact serial env Await and abort order');
    if(stop===0)assert(value.auth.headers.Authorization==='Bearer owned-ANTHROPIC_AUTH_TOKEN','auth token precedence');
    else if(stop<3)assert(value.auth.apiKey==='owned-'+names[stop]&&value.source===names[stop],'key precedence');
    else if(stop===8)assert(value.source==='workload identity federation'&&Object.keys(value.env).length===5,'all federation fields');
    else assert(value===undefined,'missing required federation value');
    rows.push({case:'ambient-'+stop,calls,trace,value});
  }
  let sync=false,rejected;try{rejected=auth.resolve(undefined)}catch{sync=true}
  assert(!sync,'destructured parameter failure is async rejection');
  try{await rejected;throw Error('missing parameter accepted')}catch(error){assert(error instanceof TypeError,'parameter TypeError')}
  return rows;
}

export async function observeAnthropicIterators(auth) {
  const assert=(ok,message)=>{if(!ok)throw Error(message)};
  const original=Array.prototype[Symbol.iterator];const signal={throwIfAborted(){}};
  const name={owned:'yielded name'};let closes=0;
  try {
    Array.prototype[Symbol.iterator]=function(){if(this[0]!=='ANTHROPIC_OAUTH_TOKEN')return original.call(this);let used=false;return{next(){if(used)return{done:true};used=true;return{done:false,value:name}},return(){closes++;return{}}}};
    const value=await auth.resolve({ctx:{env(key){return key===name?'owned-custom-key':undefined}},signal});
    assert(value.source===name&&value.auth.apiKey==='owned-custom-key'&&closes===1,'live literal Array iterator and source identity');
    const reason={owned:'rejection'},closeReason={owned:'close'};let got;
    Array.prototype[Symbol.iterator]=function(){if(this[0]!=='ANTHROPIC_OAUTH_TOKEN')return original.call(this);return{next(){return{done:false,value:'OWNED_CUSTOM'}},return(){throw closeReason}}};
    try{await auth.resolve({ctx:{env(key){return key==='OWNED_CUSTOM'?Promise.reject(reason):undefined}},signal})}catch(error){got=error}
    assert(got===reason,'original Await rejection wins ordinary IteratorClose');
    got=undefined;try{await auth.resolve({ctx:{env(key){return key==='OWNED_CUSTOM'?'owned':undefined}},signal})}catch(error){got=error}
    assert(got===closeReason,'successful return is replaced by close throw');
    let stepClose=0;got=undefined;
    Array.prototype[Symbol.iterator]=function(){if(this[0]!=='ANTHROPIC_OAUTH_TOKEN')return original.call(this);return{next(){return{done:false,get value(){throw reason}}},return(){stepClose++;return{}}}};
    try{await auth.resolve({ctx:{env(){return undefined}},signal})}catch(error){got=error}
    assert(got===reason&&stepClose===0,'IteratorValue throw does not close');
    let setterReceiver,setterValue;
    Object.defineProperty(Object.prototype,'OWNED_FEDERATION',{configurable:true,set(value){setterReceiver=this;setterValue=value}});
    try {
      Array.prototype[Symbol.iterator]=function(){if(this[0]!=='ANTHROPIC_FEDERATION_RULE_ID')return original.call(this);let used=false;return{next(){if(used)return{done:true};used=true;return{done:false,value:'OWNED_FEDERATION'}}}};
      const value=await auth.resolve({ctx:{env(key){return key==='OWNED_FEDERATION'?'owned-field':undefined}},signal});
      assert(setterReceiver===value.env&&setterValue==='owned-field'&&!Object.hasOwn(value.env,'OWNED_FEDERATION'),'Source federation assignment uses live inherited setter');
    } finally {delete Object.prototype.OWNED_FEDERATION}
    return{closes,stepClose,setterValue};
  } finally {Array.prototype[Symbol.iterator]=original}
}

// Called only by the actual API owner with genuine provider/API constructors,
// real request context/options and owned network endpoint/transport provenance.
export async function observeActualAnthropicRequest(provider, models, context, options) {
  const builtin=provider.getModels()[0];
  if(provider.id!=='anthropic'||!builtin)throw Error('actual Anthropic provider required');
  models.setProvider(provider);
  const model=models.getModel('anthropic',builtin.id);
  // Actual Models request dispatch resolves provider auth from its genuine
  // credential store/AuthContext before entering the actual API transport.
  const stream=models.streamSimple(model,context,options);
  const events=[];for await(const event of stream)events.push(event);
  return{provider:provider.id,model:model.id,events,result:await stream.result()};
}

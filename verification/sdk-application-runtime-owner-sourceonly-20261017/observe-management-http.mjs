// Genuine caller of the ORIGINAL exported function, or of the actual native
// export for later comparison. Owned fetch/signal inputs instrument this helper
// boundary; they do not qualify an HTTP transport or replace an SDK dependency.
export async function observeManagementHttp(fetchWithRetry) {
  const rows = [], originalFetch = Object.getOwnPropertyDescriptor(globalThis, 'fetch');
  const timeoutDescriptor = Object.getOwnPropertyDescriptor(AbortSignal, 'timeout');
  const errorDescriptor = Object.getOwnPropertyDescriptor(globalThis, 'Error');
  const hasDescriptor = Object.getOwnPropertyDescriptor(Set.prototype, 'has');
  const numberDescriptor = Object.getOwnPropertyDescriptor(Number, 'isFinite');
  const maxDescriptor = Object.getOwnPropertyDescriptor(Math, 'max');
  const floorDescriptor = Object.getOwnPropertyDescriptor(Math, 'floor');
  const input = {owned:'input'}, init = {headers:{owned:'header'}}, success = {status:200};
  const setFetch = fn => Object.defineProperty(globalThis,'fetch',{configurable:true,writable:true,value:fn});
  try {
    let calls = [], failures = 0;
    setFetch(function(i,o){calls.push([i===input,o===init,this===undefined]);return failures++<2?Promise.reject({owned:'transport'}):success});
    rows.push(['transport-default',await fetchWithRetry(input,init)===success,calls]);
    for(const status of [408,425,429,500,502,503,504,501]){
      let count=0,cancels=0;const response={status,body:{cancel(){cancels++}}};
      setFetch(()=>++count===1?response:success);
      const value=await fetchWithRetry(input);
      rows.push(['status',status,count,cancels,value===response,value===success]);
    }
    let order=[],count=0;
    setFetch(()=>{order.push('fetch'+(++count));return count===1?{status:503,body:{cancel(){order.push('cancel');queueMicrotask(()=>order.push('microtask'));return undefined}}}:success});
    rows.push(['cancel-await-undefined',await fetchWithRetry(input)===success,order]);
    const cancelReason={owned:'cancel'};count=0;
    setFetch(()=>++count===1?{status:503,body:{cancel(){return Promise.reject(cancelReason)}}}:success);
    rows.push(['cancel-rejection-discarded',await fetchWithRetry(input)===success,count]);
    const parent=new AbortController(),abortReason={owned:'parent'};parent.abort(abortReason);count=0;
    setFetch(()=>{count++;return success});let caught;
    try{await fetchWithRetry(input,{signal:parent.signal})}catch(reason){caught=reason}
    rows.push(['parent-before-fetch',caught===abortReason,count]);
    let signals=[],timeouts=[];count=0;
    Object.defineProperty(AbortSignal,'timeout',{configurable:true,writable:true,value(ms){timeouts.push(ms);return new AbortController().signal}});
    setFetch((_i,o)=>{signals.push(o.signal);return ++count===1?Promise.reject({owned:'once'}):success});
    rows.push(['shared-timeout',await fetchWithRetry(input,undefined,{timeoutMs:1000})===success,timeouts,signals.length,signals[0]===signals[1]]);
    let controllers=[];signals=[];count=0;
    Object.defineProperty(AbortSignal,'timeout',{configurable:true,writable:true,value(){const c=new AbortController();controllers.push(c);return c.signal}});
    setFetch((_i,o)=>{signals.push(o.signal);if(++count===1){controllers[0].abort();o.signal.throwIfAborted()}return success});
    rows.push(['attempt-timeout',await fetchWithRetry(input,undefined,{attemptTimeoutMs:4000})===success,controllers.length,signals[0]!==signals[1]]);
    Object.defineProperty(AbortSignal,'timeout',timeoutDescriptor);
    for(const reason of [{owned:'raw'},new Error('owned'), 'owned string',undefined]){
      count=0;setFetch(()=>{count++;return Promise.reject(reason)});let actual,thrown=false;
      try{await fetchWithRetry(input,undefined,{maxRetries:0})}catch(error){actual=error;thrown=true}
      rows.push(['zero-retry-raw',thrown,Object.is(actual,reason),count]);
    }
    const log=[];let reads=0;
    Object.defineProperty(Number,'isFinite',{configurable:true,get(){log.push('get-finite');return function(value){log.push(['finite',this===Number,value]);return true}}});
    Object.defineProperty(Math,'max',{configurable:true,get(){log.push('get-max');return function(a,b){log.push(['max',this===Math,a,b]);return 0}}});
    Object.defineProperty(Math,'floor',{configurable:true,get(){log.push('get-floor');return function(value){log.push(['floor',this===Math,value]);return value}}});
    const options={get maxRetries(){log.push('max-read'+(++reads));return reads}};
    setFetch(()=>success);
    rows.push(['option-callee-order',await fetchWithRetry(input,undefined,options)===success,log]);
    Object.defineProperty(Number,'isFinite',numberDescriptor);Object.defineProperty(Math,'max',maxDescriptor);Object.defineProperty(Math,'floor',floorDescriptor);
    let hasLog=[];count=0;
    Object.defineProperty(Set.prototype,'has',{configurable:true,get(){hasLog.push('get-has');return function(value){hasLog.push(['selected-has',value]);return value===503}}});
    setFetch(()=>++count===1?{get status(){hasLog.push('status');Object.defineProperty(Set.prototype,'has',{configurable:true,value(){throw new Error('late has must not be used')}});return 503},body:{cancel(){Object.defineProperty(Set.prototype,'has',hasDescriptor)}}}:success);
    rows.push(['status-callee-before-argument',await fetchWithRetry(input)===success,hasLog]);
    Object.defineProperty(Set.prototype,'has',hasDescriptor);
    const catchReason={owned:'instanceof-getter'};count=0;
    function ChangedError(){}Object.defineProperty(ChangedError,Symbol.hasInstance,{get(){throw catchReason}});
    Object.defineProperty(globalThis,'Error',{configurable:true,writable:true,value:ChangedError});
    setFetch(()=>{count++;return Promise.reject({owned:'fetch-rejection'})});caught=undefined;
    try{await fetchWithRetry(input)}catch(reason){caught=reason}
    rows.push(['catch-body-failure',caught===catchReason,count]);
  } finally {
    Object.defineProperty(globalThis,'fetch',originalFetch);
    Object.defineProperty(AbortSignal,'timeout',timeoutDescriptor);
    Object.defineProperty(globalThis,'Error',errorDescriptor);
    Object.defineProperty(Set.prototype,'has',hasDescriptor);
    Object.defineProperty(Number,'isFinite',numberDescriptor);
    Object.defineProperty(Math,'max',maxDescriptor);Object.defineProperty(Math,'floor',floorDescriptor);
  }
  return {authority:'actual-Pi8efd-management-http-caller',rows};
}

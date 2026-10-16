// Shared owned callers only. consume is either the real language for-await
// function in the reference driver or the proposed genuine native AF body.
export async function observeForAwait(consume){
 const P=Promise,rows=[];
 const describe=value=>value instanceof P?{promise:true}:value;
 const cases=[
  {name:'string codepoints',input:()=> 'A\u{1f600}B'},
  {name:'array plain',input:()=>[1,2]},
  {name:'array fulfilled promises',input:()=>[P.resolve('first'),P.resolve('second')]},
  ...['normal','break','return','throw'].map(mode=>({name:'sync captured next '+mode,mode})),
  {name:'null async method falls back',asyncMethod:null},
  {name:'undefined async method falls back'},
  {name:'async method raw getter',fail:'async getter'},
  {name:'noncallable async method',asyncMethod:17},
  {name:'sync method raw getter',fail:'sync getter'},
  {name:'sync method noncallable',syncMethod:17},
  {name:'sync method returns primitive',primitiveIterator:true},
  {name:'sync next getter raw',fail:'next getter'},
  {name:'sync next noncallable',badNext:true},
  {name:'sync next raw throw',fail:'next call'},
  {name:'sync next primitive result',primitiveResult:true},
  {name:'sync done getter raw',fail:'done'},
  {name:'sync value getter raw',fail:'value'},
  {name:'sync yielded promise rejects',rejectedValue:true},
  {name:'sync yielded then getter throws',badThen:true},
  {name:'sync terminal promise rejects',terminalReject:true},
  ...['getter','call','rejection','primitive','absent'].flatMap(close=>['break','throw'].map(mode=>({name:'sync close '+close+' '+mode,close,mode}))),
  {name:'true async iterator promise value',async:true},
  {name:'true async primitive next result',async:true,primitiveResult:true},
  {name:'true async next sync throw',async:true,fail:'next call'},
  {name:'true async next rejects',async:true,rejectedNext:true},
  {name:'true async done getter raw',async:true,fail:'done'},
  {name:'true async value getter raw',async:true,fail:'value'},
  ...['getter','call','rejection','primitive','absent'].flatMap(close=>['break','throw'].map(mode=>({name:'async close '+close+' '+mode,async:true,close,mode}))),
  {name:'intrinsic promise ignores global replacement',replacePromise:true}
 ];
 for(const config of cases){
  const trace=[],raw={acquire:{owned:'acquire'},next:{owned:'next'},value:{owned:'value'},body:{owned:'body'},close:{owned:'close'}},values=[];let index=0,nextGets=0,globalReads=0;
  const fail=(name,reason)=>{trace.push(name);if(config.fail===name)throw reason};
  const original=function(){fail('next call',raw.next);if(config.rejectedNext)return P.reject(raw.next);if(config.primitiveResult)return 7;const terminal=index>=2;const position=index++;return {get done(){fail('done',raw.next);return terminal},get value(){fail('value',raw.value);if(terminal&&config.terminalReject)return P.reject(raw.value);if(!terminal&&config.rejectedValue)return P.reject(raw.value);if(!terminal&&config.badThen)return {get then(){trace.push('then getter');throw raw.value}};return terminal?'terminal':config.async?P.resolve(position):position}}};
  const iterator={get next(){nextGets++;fail('next getter',raw.next);return config.badNext?7:function(...args){trace.push(['next receiver',this===iterator,'argc',args.length]);return Reflect.apply(original,this,args)}},get return(){trace.push('return getter');if(config.close==='getter')throw raw.close;if(config.close==='absent')return undefined;return function(...args){trace.push(['return receiver',this===iterator,'argc',args.length]);if(config.close==='call')throw raw.close;if(config.close==='primitive')return 7;if(config.async&&config.close==='rejection')return P.reject(raw.close);return {get done(){trace.push('return done');return true},get value(){trace.push('return value');return config.close==='rejection'?P.reject(raw.close):P.resolve('closed')}}}}};
  const input=config.input?config.input():{get [Symbol.asyncIterator](){fail('async getter',raw.acquire);if(config.async)return function(){trace.push('async method');return iterator};return config.asyncMethod},get [Symbol.iterator](){fail('sync getter',raw.acquire);if(config.syncMethod!==undefined)return config.syncMethod;return function(){trace.push('sync method');return config.primitiveIterator?7:iterator}}};
  const descriptor=Object.getOwnPropertyDescriptor(globalThis,'Promise');
  const checkpoints=P.resolve().then(()=>trace.push('checkpoint1')).then(()=>trace.push('checkpoint2'));
  try{
   if(config.replacePromise)Object.defineProperty(globalThis,'Promise',{configurable:true,get(){globalReads++;throw raw.acquire}});
   let result,error;try{result=await consume(input,config.mode??'normal',async function(value,count){trace.push(['visit',describe(value),count]);values.push(describe(value));if(count===1)Object.defineProperty(iterator,'next',{configurable:true,value(){throw Error('Captured next was reread')}})},raw.body)}catch(failure){error=failure}
   await checkpoints;
   const rawName=Object.keys(raw).find(key=>raw[key]===error);
   rows.push({name:config.name,trace,nextGets,globalReads,values,result:result?{kind:result.kind,values:result.values.map(describe)}:undefined,error:error===undefined?undefined:{raw:rawName,name:error?.name,message:error?.message}});
  }finally{if(descriptor)Object.defineProperty(globalThis,'Promise',descriptor);else delete globalThis.Promise}
 }
 // These are genuine language async-generator delegation probes, not an
 // exposed/fabricated AsyncFromSync wrapper. Keep their observations separate.
 for(const mode of ['next','return','throw','missing throw','throw closes with raw getter','return primitive']){
  const trace=[],raw={owned:'delegation'},iter={next(){trace.push('next');return {done:false,value:P.resolve('first')}}};
  if(mode!=='missing throw'&&mode!=='throw closes with raw getter')iter.throw=function(reason){trace.push(['throw',reason===raw]);return {done:true,value:P.resolve('thrown')}};
  Object.defineProperty(iter,'return',{get(){trace.push('return getter');if(mode==='throw closes with raw getter')throw raw;return function(value){trace.push(['return',value===raw]);return mode==='return primitive'?7:{done:true,value:P.resolve('returned')}}}});
  const input={[Symbol.iterator](){trace.push('iterator');return iter}};
  async function* delegate(){return yield* input}
  const generator=delegate(),first=await generator.next();let result,error;
  try{result=mode==='next'?await generator.next():mode.startsWith('return')?await generator.return(raw):await generator.throw(raw)}catch(failure){error=failure}
  rows.push({name:'language delegate '+mode,trace,first,result,error:error===undefined?undefined:{rawSame:error===raw,name:error?.name,message:error?.message}});
  if(!result?.done&&!error){trace.push('caller cleanup return');await generator.return()}
 }
 return rows;
}

// Genuine language caller fixture only; never a production Agent implementation.
export async function observeAgentRouting(Agent){
 const rows=[];
 async function probe(id,method,make,args=[]){
  const trace=[],marker={owned:id};const receiver=make(trace,marker);let result,immediate;
  try{result=Reflect.apply(Agent.prototype[method],receiver,args);immediate={returned:true,promise:result instanceof Promise};trace.push('caller:return')}
  catch(reason){immediate={returned:false,marker:reason===marker,type:typeof reason,name:reason?.name,message:reason?.message};trace.push('caller:throw')}
  let settled;if(immediate.returned){queueMicrotask(()=>trace.push('caller:microtask'));try{const value=await result;settled={fulfilled:true,undefined:value===undefined};trace.push('caller:fulfilled')}catch(reason){settled={fulfilled:false,marker:reason===marker,type:typeof reason,name:reason?.name,message:reason?.message};trace.push('caller:rejected')}}
  rows.push({id,immediate,settled,trace});
 }
 await probe('prompt-live-order','prompt',(trace)=>({get activeRun(){trace.push('active');return null},get normalizePromptInput(){trace.push('normalize:get');return function(input,images){trace.push('normalize:call:'+String(this.activeRun===null));return [input,images]};},get runPromptMessages(){trace.push('run:get');return function(messages){trace.push('run:call:'+messages.length);return 42}}}),['owned',[]]);
 await probe('prompt-active','prompt',()=>({activeRun:true}));
 await probe('prompt-active-getter-reason','prompt',(trace,marker)=>({get activeRun(){trace.push('active');throw marker}}));
 await probe('prompt-normalizer-reason','prompt',(trace,marker)=>({activeRun:null,normalizePromptInput(){trace.push('normalize');throw marker}}));
 await probe('prompt-run-getter-reason','prompt',(trace,marker)=>({activeRun:null,normalizePromptInput(){return []},get runPromptMessages(){trace.push('run:get');throw marker}}));
 await probe('prompt-thenable-fulfilled','prompt',(trace)=>({activeRun:null,normalizePromptInput(){return []},runPromptMessages(){trace.push('run');return{get then(){trace.push('then:get');return function(resolve){trace.push('then:call');resolve('discarded')}}}}));
 await probe('prompt-thenable-raw-rejection','prompt',(trace,marker)=>({activeRun:null,normalizePromptInput(){return []},runPromptMessages(){return{then(resolve,reject){trace.push('then:reject');reject(marker)}}}}));
 function continuation(trace,role,steering=[],follow=[]){return{activeRun:null,_state:{messages:role===undefined?[]:[{role}]},steeringQueue:{drain(){trace.push('steering:drain');return steering}},followUpQueue:{drain(){trace.push('followup:drain');return follow}},runPromptMessages(messages,options){trace.push('runPrompt:'+messages.length+':'+String(options?.skipInitialSteeringPoll));return 'discarded'},runContinuation(){trace.push('runContinuation');return 'discarded'}}}
 await probe('continue-empty-short-circuit','continue',(trace)=>({activeRun:null,_state:{messages:[]},get steeringQueue(){trace.push('unexpected:steering');throw Error('unreachable')}}));
 await probe('continue-system-only','continue',(trace)=>continuation(trace,'system'));
 await probe('continue-steering','continue',(trace)=>continuation(trace,'assistant',[{role:'user'}]));
 await probe('continue-followup','continue',(trace)=>continuation(trace,'assistant',[],[{role:'user'}]));
 await probe('continue-assistant-empty','continue',(trace)=>continuation(trace,'assistant'));
 await probe('continue-user','continue',(trace)=>continuation(trace,'user'));
 await probe('continue-undefined-receiver','continue',()=>undefined);
 await probe('continue-live-state-order','continue',(trace)=>{const item={get role(){trace.push('role');return 'user'}};const values=new Proxy([item],{get(target,key,receiver){trace.push('messages:'+String(key));return Reflect.get(target,key,receiver)}});return{activeRun:null,get _state(){trace.push('_state');return{get messages(){trace.push('messages:get');return values}}},get runContinuation(){trace.push('continuation:get');return function(){trace.push('continuation:call');return 0}}}});
 return{authority:'actual-Pi1.3-8efd-Agent-routing',rows};
}

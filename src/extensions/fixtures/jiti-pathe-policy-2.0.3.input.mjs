// Additive ORIGINAL subject: actual pathe2.0.3 named path/utils exports.
// Controlled ordinary throws observe Source ownership/close semantics; native
// allocation controls are separate. No expected JSON or Node path substitute.
const {path,utils}=globalThis.nativePathePolicySubject;
const rows=[];
function observe(name,run){try{rows.push({name,value:run()})}catch(error){rows.push({name,error:{name:error?.name,message:error?.message}})}}
for(const getter of [true,false])observe('normal-close-'+(getter?'getter':'call'),()=>{
 const descriptor=Object.getOwnPropertyDescriptor(Array.prototype,'sort'),reason={ordinary:'normal'},log=[];
 Object.defineProperty(Array.prototype,'sort',{configurable:true,value:function(compare){const pair={[Symbol.iterator](){return{next(){log.push('next');return{done:false,value:'a'}},get return(){log.push('get return');if(getter)throw reason;return function(){log.push('call return');throw reason}}}}};return compare(pair,['b','/root'])}});
 let caught;try{utils.normalizeAliases({a:'/one',b:'/two'})}catch(error){caught=error}finally{Object.defineProperty(Array.prototype,'sort',descriptor)}
 return{same:caught===reason,log};
});
for(const getter of [true,false])observe('abrupt-close-'+(getter?'getter':'call'),()=>{
 const descriptor=Object.getOwnPropertyDescriptor(Array.prototype,Symbol.iterator),primary={ordinary:'primary'},cleanup={ordinary:'cleanup'},log=[];
 Object.defineProperty(Array.prototype,Symbol.iterator,{configurable:true,value:function(){return{next(){return{done:false,value:{toString(){log.push('primary');throw primary}}}},get return(){log.push('get return');if(getter)throw cleanup;return function(){log.push('call return');throw cleanup}}}}});
 let caught;try{path.join('owned')}catch(error){caught=error}finally{Object.defineProperty(Array.prototype,Symbol.iterator,descriptor)}
 return{same:caught===primary,log};
});
observe('public-constructor-prototype-reason',()=>{const reason={ordinary:'prototype'},log=[];const target=new Proxy(function(){},{get(target,key,receiver){if(key==='prototype'){log.push('prototype');throw reason}return Reflect.get(target,key,receiver)}});let caught;try{Reflect.construct(path.join,['owned'],target)}catch(error){caught=error}return{same:caught===reason,log}});
observe('public-ordinary-raw-reason',()=>{const descriptor=Object.getOwnPropertyDescriptor(String.prototype,'replace'),reason={ordinary:'replace'};Object.defineProperty(String.prototype,'replace',{configurable:true,value:function(){throw reason}});let caught;try{path.normalize('owned')}catch(error){caught=error}finally{Object.defineProperty(String.prototype,'replace',descriptor)}return caught===reason});
globalThis.nativePathePolicyObservation={count:rows.length,rows};

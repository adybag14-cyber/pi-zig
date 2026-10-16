// Prepared original Pi parser reentry/getter controls; no expected output.
const {parseGitUrl,hosted}=GitAPI,rows=[];
{
 const descriptor=Object.getOwnPropertyDescriptor(Object.prototype,'ref'),assign=Object.assign,trace=[],marker={repo:'lazy'};let reads=0;
 try{
  Object.assign=function(target,host,fields){if(fields?.project==='lazy-repo')trace.push('hosted-constructor');return Reflect.apply(assign,this,arguments)};
  Object.defineProperty(Object.prototype,'ref',{configurable:true,get(){reads++;trace.push(`ref-${reads}`);if(reads===1)Object.defineProperty(this,'repo',{configurable:true,get(){trace.push('repo-throw');throw marker}});return undefined}});
  let failure;try{parseGitUrl('https://github.com/repo-order/lazy-repo')}catch(error){failure=error};rows.push({name:'false-ref-skips-repo-until-after-real-hosted-call',same:failure===marker,trace});
 }finally{Object.assign=assign;if(descriptor)Object.defineProperty(Object.prototype,'ref',descriptor);else delete Object.prototype.ref}
}
{
 const descriptor=Object.getOwnPropertyDescriptor(Object.prototype,'ref'),trace=[];let reads=0;
 try{Object.defineProperty(Object.prototype,'ref',{configurable:true,get(){reads++;trace.push(`ref-${reads}`);if(reads===2)this.repo='ssh://changed.test/other/repository';return undefined}});const result=parseGitUrl('https://github.com/repo-order/changed-repo');rows.push({name:'repo-reread-after-ref-getter-mutation',result,trace})}
 finally{if(descriptor)Object.defineProperty(Object.prototype,'ref',descriptor);else delete Object.prototype.ref}
}
{
 const original=String.prototype.slice,trace=[],input='user@github.com:owner/repo';
 try{String.prototype.slice=function(...args){const value=Reflect.apply(original,this,args);if(String(this)===input){trace.push({slice:args});if(args[0]===0&&args.length===2)return {[Symbol.toPrimitive](hint){trace.push({hint});return value}}}return value};const parsed=hosted.parseUrl(input);rows.push({name:'SCP-correction-default-addition-before-second-slice',trace,parsed:parsed&&{protocol:parsed.protocol,hostname:parsed.hostname,pathname:parsed.pathname}})}
 finally{String.prototype.slice=original}
}
globalThis.gitHostRepoOrderRows=rows;globalThis.gitSourceHostedRows=rows;globalThis.gitSourceHostedComplete=true;

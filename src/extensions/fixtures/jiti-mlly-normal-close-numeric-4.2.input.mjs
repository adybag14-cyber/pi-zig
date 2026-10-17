// Additive ORIGINAL subject controls. The Node bindings below are the genuine
// mutable default export and named synchronization binding, never a namespace
// clone or a user-supplied synchronization collaborator. The subject supplies
// only the actual pinned4.2 moduleResolve/defaultGetFormatWithoutErrors helpers.
import nodeURL from 'node:url';
import {syncBuiltinESMExports} from 'node:module';
import {observeMllyBoundaries} from './jiti-mlly-boundaries-4.2.input.mjs';
export function observeMllyNormalCloseNumeric(subject){
 const result=observeMllyBoundaries({...subject,nodeURL,syncBuiltinESMExports});
 for(const getter of [true,false]){
  const id='normal-close-original-'+(getter?'getter':'call'),reason={original:id},log=[];
  const extensions={[Symbol.iterator](){let used=false;return{next(){log.push('next');if(used)return{done:true};used=true;return{done:false,value:'.js'}},get return(){log.push('get return');if(getter)throw reason;return function(){log.push('call return');throw reason}}}}};
  try{result.rows.push({id,value:{returned:subject.mlly.resolveSync('./src/local',{url:new URL('entry.mjs',subject.fixtureRootURL),extensions}),log}})}catch(actual){result.rows.push({id,value:{same:actual===reason,log}})}
 }
 for(const kind of ['string-zero','object-zero','nan','bigint-zero','tiny-nonzero']){
  const id='format-postdecrement-'+kind,log=[];
  const length=kind==='string-zero'?'0':kind==='object-zero'?{[Symbol.toPrimitive](hint){log.push(['numeric',hint]);return 0}}:kind==='nan'?NaN:kind==='bigint-zero'?0n:Number.MIN_VALUE;
  const pathname={length,codePointAt(index){log.push(['codePointAt',String(index)]);return 47},slice(index){log.push(['slice',String(index)]);return '.mjs'}};
  const url=new URL('file:///C:/owned/nonexistent.mjs');Object.defineProperty(url,'pathname',{configurable:true,get(){log.push(['pathname']);return pathname}});
  try{result.rows.push({id,value:{format:subject.defaultGetFormatWithoutErrors(url,{}),log}})}catch(reason){result.rows.push({id,error:{name:reason?.name,message:reason?.message},log})}
 }
 result.count=result.rows.length;return result;
}

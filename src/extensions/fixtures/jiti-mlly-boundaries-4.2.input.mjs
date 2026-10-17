// Additive ORIGINAL helper controls. Subject supplies the actual pinned4.2
// exported moduleResolve/defaultGetFormatWithoutErrors and genuine Node imports.
// No candidate output or expected answers are encoded in this program.
export function observeMllyBoundaries(subject){
 const rows=[];
 function observe(id,run){try{rows.push({id,value:run()})}catch(reason){rows.push({id,error:{name:reason?.name,message:reason?.message}})}}
 observe('finalize-descriptor-callee-before-string',()=>{
  const originalFile=subject.nodeURL.fileURLToPath,originalString=globalThis.String,define=Object.defineProperty;
  const defineDescriptor=Object.getOwnPropertyDescriptor(Object,'defineProperty'),stringDescriptor=Object.getOwnPropertyDescriptor(globalThis,'String');
  const reason={original:'fileURLToPath'},log=[];
  subject.nodeURL.fileURLToPath=function(...args){Reflect.apply(originalFile,this,args);throw reason};subject.syncBuiltinESMExports();
  define(Object,'defineProperty',{configurable:true,get(){log.push('get defineProperty');return function(...args){log.push('call defineProperty');return Reflect.apply(define,this,args)}}});
  define(globalThis,'String',{configurable:true,writable:true,value:function(...args){log.push('call String');return Reflect.apply(originalString,undefined,args)}});
  try{let actual;try{subject.moduleResolve('./missing.mjs',new URL('file:///C:/owned/base.mjs'),new Set(['node','import']))}catch(error){actual=error}return{same:actual===reason,log,input:reason.input,module:reason.module}}
  finally{define(Object,'defineProperty',defineDescriptor);define(globalThis,'String',stringDescriptor);subject.nodeURL.fileURLToPath=originalFile;subject.syncBuiltinESMExports()}
 });
 for(const [id,address]of [['file','file:///C:/owned/a.mjs'],['node','node:fs'],['http','http://example.invalid/a'],['https','https://example.invalid/a'],['data-js','data:text/javascript,export%20default%201'],['data-json','data:application/json,%7B%7D'],['unknown','custom:owned']])observe('format-protocol-'+id,()=>{
  const url=new URL(address),protocol=url.protocol,pathname=url.pathname,log=[];
  Object.defineProperty(url,'protocol',{configurable:true,get(){log.push('protocol');return protocol}});
  Object.defineProperty(url,'pathname',{configurable:true,get(){log.push('pathname');return pathname}});
  return{format:subject.defaultGetFormatWithoutErrors(url,{parentURL:'file:///C:/owned/base.mjs'}),log}
 });
 return{count:rows.length,rows};
}

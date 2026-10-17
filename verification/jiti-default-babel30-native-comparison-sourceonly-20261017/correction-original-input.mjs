// Prepared additive original observations only. A separately granted bounded
// owner supplies the actual pinned default Babel function and physical filename.
// No custom transform, native-produced expected result or execution occurs here.
export default function observe(actualDefaultBabel, filename) {
  if(typeof actualDefaultBabel!=='function'||typeof filename!=='string')throw Error('actual original backend/physical label required');
  const rows=[];
  const failure=error=>({type:typeof error,name:error?.name,message:error?.message,code:error?.code,loc:error?.loc,stack:error?.stack});
  function capture(id, source, babel, extra=()=>({})) {
    const row={id};
    try{const result=actualDefaultBabel({source,ts:true,interopDefault:true,retainLines:false,filename,babel});row.result={keys:Reflect.ownKeys(result).map(String),code:result.code,error:result.error?failure(result.error):undefined};}
    catch(error){row.thrown=failure(error);}
    Object.assign(row,extra());rows.push(row);
  }
  for(const [name,line]of [['LS','\u2028'],['PS','\u2029']]){
    capture('return-'+name,'export function f(){return'+line+'owned;}',undefined);
    capture('async-'+name,'export function f(){let async=7;async'+line+'function g(){return 1}return g()}',undefined);
    capture('postfix-'+name,'export function f(){let value=1;value'+line+'++value;return value}',undefined);
  }
  capture('numeric-member-gap','export const value=1 .toString();',undefined);
  capture('regex-word-gap','export const value=/x/ instanceof RegExp;',undefined);
  for(const nonenumerable of [false,true]){
    let executed=0;const plugin=()=>{executed++;return{}};
    const list=nonenumerable?Object.defineProperty([],'0',{value:plugin,enumerable:false}):[plugin];
    capture('nonempty-'+(nonenumerable?'nonenumerable':'array'),'export const value=1;',{plugins:list},()=>({executed}));
  }
  const log=[],list=[];
  list[Symbol.iterator]=function*(){log.push('iterator');yield()=>({});log.push('done')};
  capture('empty-array-custom-iterator','export const value=1;',{plugins:list},()=>({log}));
  const rereadLog=[],first=[],second={*[Symbol.iterator](){rereadLog.push('iterator');yield()=>({});rereadLog.push('done')}};
  let reads=0;const babel={};Object.defineProperty(babel,'plugins',{get(){rereadLog.push('get'+(++reads));return reads===1?first:second}});
  capture('plugins-reread-after-isArray','export const value=1;',babel,()=>({log:rereadLog}));
  return {scope:'additional-original-only-not-original30-substitution',rows,expectedCreated:false};
}

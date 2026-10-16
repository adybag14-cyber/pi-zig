import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {compactionPolicy} from 'file:///C:/Users/adyba/pi-upstream-source-0fbdbd3-20261016/packages/durable/src/harness/compaction.ts';
import {isRetryableAssistantError} from 'file:///C:/Users/adyba/pi-upstream-source-0fbdbd3-20261016/packages/ai/src/utils/retry.ts';
if(process.version!=='v24.14.0')throw Error('Node24.14.0 required');
globalThis.latestPolicy=compactionPolicy;
globalThis.latestRetry=isRetryableAssistantError;
const root='C:/Users/adyba/pi-zig-upstream-0fb-20261016/src/extensions/fixtures/';
const document={sourceHead:'0fbdbd3f8ab1876ac260c0f08226a400759323b8',programs:[]};
for(const [name,globalRows,complete,count]of[['policy','upstream0fbRows','upstream0fbComplete',17],['public','upstream0fbPublicRows','upstream0fbPublicComplete',6],['select','upstream0fbSelectRows','upstream0fbSelectComplete',4]]){
 const path=root+'upstream-0fb-'+name+'.input.txt',input=readFileSync(path),sha256=createHash('sha256').update(input).digest('hex');
 let timer;try{await Promise.race([import('data:text/javascript,'+encodeURIComponent(input.toString('utf8'))),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Bounded source program timed out: '+name)),20000)})]);}finally{clearTimeout(timer)}
 if(globalThis[complete]!==true||globalThis[globalRows].length!==count)throw Error('Incomplete genuine source program '+name);
 document.programs.push({name,inputSha256:sha256,cases:count,rows:globalThis[globalRows]});
}
writeFileSync(process.argv[2],JSON.stringify(document,null,2)+'\n');
process.stdout.write(JSON.stringify({sourceHead:document.sourceHead,programs:document.programs.map(({name,cases,inputSha256})=>({name,cases,inputSha256}))})+'\n');

import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {dirname,resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
const {ModelRuntime}=await import(pathToFileURL('C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/coding-agent/src/core/model-runtime.ts'));
const fixtureCwd=resolve(dirname(process.argv[2]),'sandbox').replaceAll('\\','/');mkdirSync(fixtureCwd,{recursive:true});
globalThis.modelRuntimeCreateAPI={ModelRuntime,fixtureCwd};
const input=readFileSync(process.argv[3]);let timer;
try{await Promise.race([import('data:text/javascript,'+encodeURIComponent(input.toString('utf8'))),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('ModelRuntime.create Source8 settle deadline')),10000)})]);}finally{clearTimeout(timer)}
const expectedErrors=new Set(['actual-caller-abort-reason','actual-finally-clear-raw-replacement']);
for(const row of modelCreateRows){if(Boolean(row.error)!==expectedErrors.has(row.name))throw Error('Unexpected original ModelRuntime.create outcome '+JSON.stringify(row));if(row.error&&!row.error.raw)throw Error('Original raw reason identity was replaced')}
writeFileSync(process.argv[2],JSON.stringify({sourceHead:'4954d760504c11df9b2cbdc040346107b6a8153d',cases:8,inputSha256:createHash('sha256').update(input).digest('hex'),scope:'Original unchanged ModelRuntime static create and full original class/Models42/auth/config/store/provider wrappers. No provider network refresh is enabled; timers run only with refreshOnCreate:false and are really cleared. Source property evaluation, default actual AuthStorage, caller store, abort and finally raw replacement.',rows:modelCreateRows},null,2));

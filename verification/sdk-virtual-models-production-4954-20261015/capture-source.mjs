import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
const source='C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/coding-agent/src/core/virtual-models.ts';
globalThis.virtualModelsAPI=await import(pathToFileURL(source));
const input=readFileSync(process.argv[3]);let timer;
try{await Promise.race([import('data:text/javascript,'+encodeURIComponent(input.toString('utf8'))),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Virtual Models Source36 10s settle deadline')),10000)})]);}finally{clearTimeout(timer)}
const expectedErrors=new Set(['virtual-null-error','virtual-raw-getter','latest-raw-getter','branch-raw-lookup','catalog-raw-getter']);
if(virtualModelsRows.length!==36)throw Error('Expected36 original namespace cases; observed '+virtualModelsRows.length);
for(const row of virtualModelsRows){if(Boolean(row.error)!==expectedErrors.has(row.name))throw Error('Unexpected actual Source outcome '+JSON.stringify(row));if(row.name.endsWith('getter')&&row.error&&!row.error.raw)throw Error('Raw getter reason changed')}
writeFileSync(process.argv[2],JSON.stringify({sourceHead:'4954d760504c11df9b2cbdc040346107b6a8153d',cases:virtualModelsRows.length,inputSha256:createHash('sha256').update(input).digest('hex'),scope:'Original virtual-models namespace and genuine pi-ai imports unchanged. Caller-owned provider implementations exercise actual namespace receiver, getter, spread, filtering, identity and lazy stream contracts. Source observation alone does not qualify native namespace or whole Pi.',rows:virtualModelsRows},null,2));

import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
const source='C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/coding-agent/src/core/runtime-credentials.ts';
const {RuntimeCredentials}=await import(pathToFileURL(source));
globalThis.runtimeCredentialsAPI={RuntimeCredentials};
const input=readFileSync(process.argv[3]);let timer;
try{await Promise.race([import('data:text/javascript,'+encodeURIComponent(input.toString('utf8'))),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Credential Source20 10s settle deadline')),10000)})]);}finally{clearTimeout(timer)}
const expectedErrors=new Set(['store-read-raw-rejection','read-abort-before-store','list-abort-after-await','delete-abort-before-store']);
for(const row of credentialRows){if(Boolean(row.error)!==expectedErrors.has(row.name))throw Error('Unexpected original Source credential outcome '+JSON.stringify(row));if(row.error&&!row.error.raw)throw Error('Raw credential reason identity was replaced')}
writeFileSync(process.argv[2],JSON.stringify({sourceHead:'4954d760504c11df9b2cbdc040346107b6a8153d',cases:20,inputSha256:createHash('sha256').update(input).digest('hex'),scope:'Original ordinary RuntimeCredentials class unchanged; valid caller CredentialStore callbacks, raw reasons, live properties, Map constructor captured across await, overrides and abort/async ownership. No model/provider namespace substitution.',rows:credentialRows},null,2));

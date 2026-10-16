import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {createModels,ModelsError} from 'file:///C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/ai/src/models.ts';
import {InMemoryCredentialStore} from 'file:///C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/ai/src/auth/credential-store.ts';
import {anthropicProvider} from 'file:///C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/ai/src/providers/anthropic.ts';
import {anthropicOAuth} from 'file:///C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/ai/src/auth/oauth/anthropic.ts';
import {envApiKeyAuth} from 'file:///C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/ai/src/auth/helpers.ts';
import {resolveProviderAuth,refreshStoredOAuthCredential} from 'file:///C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/ai/src/auth/resolve.ts';
import {runModelsAuthCases,modelsAuthCaseIds} from './models-auth-4954-cases-20261016.mjs';
const tree='C:/Users/adyba/pi-zig-native-models-auth-methods-20261016/';
const rawErrors=[],previousEnv=new Map(),originalFetch=globalThis.fetch;
const deadline=setTimeout(()=>{console.error('Actual Models auth Source69 internal deadline');process.exit(124)},60000);
const fixture={
 rawError(id,error){rawErrors.push({id,name:error?.name,message:error?.message,code:error?.code,stack:error?.stack,constructor:error?.constructor?.name})},
 setEnv(name,value){if(name!=='PI_MODELS_AUTH_4954_KEY')throw Error('Fixture environment escaped scope');if(!previousEnv.has(name))previousEnv.set(name,process.env[name]);process.env[name]=value},
 forceGC(){if(typeof globalThis.gc!=='function')throw Error('Real source GC unavailable');globalThis.gc()}
};
let output;
try{
 globalThis.fetch=()=>{throw Error('No network permitted in Models auth Source69')};
 const observed=await runModelsAuthCases({createModels,ModelsError,InMemoryCredentialStore,anthropicProvider,anthropicOAuth,envApiKeyAuth,resolveProviderAuth,refreshStoredOAuthCredential},fixture);
 if(modelsAuthCaseIds.length!==69||observed.rows.length!==69||observed.rows.some((row,index)=>row.id!==modelsAuthCaseIds[index]))throw Error('Strict original Models auth69 inventory mismatch');
 const input=fs.readFileSync(tree+'src/extensions/fixtures/models-auth-4954-cases.input.txt','utf8');
 output={sourceHead:'4954d760504c11df9b2cbdc040346107b6a8153d',runtime:process.version,count:69,inputSha256:createHash('sha256').update(input).digest('hex'),caseIds:modelsAuthCaseIds,rows:observed.rows,rawErrors,network:false,full_pi_qualified:false};
}finally{
 globalThis.fetch=originalFetch;
 for(const [name,value]of previousEnv)if(value===undefined)delete process.env[name];else process.env[name]=value;
 clearTimeout(deadline);
}
const evidence=path.resolve('C:/Users/adyba/pi-zig-update-evidence-20261003');
const target=path.resolve(process.argv[2]??'');
if(path.dirname(target)!==evidence||!path.basename(target).startsWith('models-auth-4954-source69-')||fs.existsSync(target))throw Error('Fresh contained owned output required');
fs.writeFileSync(target,JSON.stringify(output,null,2)+'\n');
console.log(JSON.stringify({count:69,rawErrors:rawErrors.length,network:false}));

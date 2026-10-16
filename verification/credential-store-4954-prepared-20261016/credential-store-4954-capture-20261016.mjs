import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {InMemoryCredentialStore} from 'file:///C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/ai/src/auth/credential-store.ts';
import {credentialStoreCaseIds,runCredentialStoreCases} from './credential-store-4954-cases-20261016.mjs';
const tree='C:/Users/adyba/pi-zig-native-models-auth-methods-20261016/',rawErrors=[];
const deadline=setTimeout(()=>{console.error('Actual CredentialStore Source20 internal deadline');process.exit(124)},60000);
let output;
try{
 const {rows}=await runCredentialStoreCases({InMemoryCredentialStore},{rawError(id,error){rawErrors.push({id,name:error?.name,message:error?.message,stack:error?.stack,constructor:error?.constructor?.name})}});
 if(credentialStoreCaseIds.length!==20||rows.length!==20||rows.some((row,index)=>row.id!==credentialStoreCaseIds[index]))throw Error('Strict original CredentialStore20 inventory mismatch');
 const input=fs.readFileSync(tree+'src/extensions/fixtures/credential-store-4954-cases.input.txt','utf8');
 output={sourceHead:'4954d760504c11df9b2cbdc040346107b6a8153d',sourcePackageVersion:JSON.parse(fs.readFileSync('C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/ai/package.json','utf8')).version,runtime:process.version,count:20,inputSha256:createHash('sha256').update(input).digest('hex'),caseIds:credentialStoreCaseIds,rows,rawErrors,network:false,full_pi_qualified:false};
}finally{clearTimeout(deadline)}
const evidence=path.resolve('C:/Users/adyba/pi-zig-update-evidence-20261003'),target=path.resolve(process.argv[2]??'');
if(path.dirname(target)!==evidence||!path.basename(target).startsWith('credential-store-4954-source20-')||fs.existsSync(target))throw Error('Fresh contained owned output required');
fs.writeFileSync(target,JSON.stringify(output,null,2)+'\n');
console.log(JSON.stringify({count:20,rawErrors:rawErrors.length,network:false}));

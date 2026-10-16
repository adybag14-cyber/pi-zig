import fs from 'node:fs';
import {setTimeout,clearTimeout} from 'node:timers';
delete process.env.PI_PACKAGE_DIR;
const config=await import('file:///C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/coding-agent/src/config.ts');
const sourcePackage={version:config.VERSION,packageDir:config.getPackageDir(),packageJsonPath:config.getPackageJsonPath()};
if(sourcePackage.version!=='1.3.0'||sourcePackage.packageDir.replaceAll('\\','/')!=='C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/coding-agent')throw Error('Actual original package identity');
const api=await import('file:///C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/ai/src/models.ts');
const {run}=await import('./models-class-4954-cases-20261016.mjs');
globalThis.fetch=()=>{throw Error('Actual Models class fixture forbids network')};
const output=process.argv[2];
if(!output||fs.existsSync(output))throw Error('Fresh owned output required');
const timer=setTimeout(()=>{throw Error('Owned actual Models class Source18 fixture exceeded ten seconds')},10000);
let rows;
try{rows=await run(api)}finally{clearTimeout(timer)}
fs.writeFileSync(output,JSON.stringify({authority:'Actual unchanged original ModelsImpl and createProvider bodies; owned callback inputs only',sourceHead:'4954d760504c11df9b2cbdc040346107b6a8153d',sourcePackage,actualNode:{version:process.version,executable:process.execPath},packageOverrideAbsent:!Object.hasOwn(process.env,'PI_PACKAGE_DIR'),network:false,cases:rows.length,rows},null,2),{flag:'wx'});

// Actual immutable Source modules. Inventory contains names/paths, never results.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {setTimeout as ownerSetTimeout,clearTimeout as ownerClearTimeout} from 'node:timers';
import * as models from 'file:///C:/Users/adyba/pi-upstream-source-ae7b16d-20261015/packages/ai/src/models.ts';
import * as all from 'file:///C:/Users/adyba/pi-upstream-source-ae7b16d-20261015/packages/ai/src/providers/all.ts';
import {withOpenCodeSessionHeader} from 'file:///C:/Users/adyba/pi-upstream-source-ae7b16d-20261015/packages/ai/src/providers/opencode-headers.ts';
import {cloudflareStreams,cloudflareClassifier,resolveCloudflareModel} from 'file:///C:/Users/adyba/pi-upstream-source-ae7b16d-20261015/packages/ai/src/providers/cloudflare-stream.ts';
import {run} from '../../src/extensions/native_ai_provider_factories_fixture.mjs';
const [ownedDirectory,output]=process.argv.slice(2);
if(!ownedDirectory||!output||fs.existsSync(ownedDirectory)||fs.existsSync(output))throw Error('Fresh unique owned paths required');
fs.mkdirSync(ownedDirectory,{recursive:true});
fs.writeFileSync(path.join(ownedDirectory,'owned-fake-provider-config.json'),JSON.stringify({owned:true,account:'owned-account',project:'owned-project'}),{flag:'wx'});
const directory=path.dirname(fileURLToPath(import.meta.url));
const inventory=JSON.parse(fs.readFileSync(path.join(directory,'source-factory-inventory.json'),'utf8'));
if(inventory.length!==42||new Set(inventory.map(row=>row.factory)).size!==42)throw Error('Original factory declaration inventory');
const factories={};
for(const row of inventory){const namespace=await import(pathToFileURL(row.source_path).href);if(typeof namespace[row.factory]!=='function')throw Error('Original export missing '+row.factory);factories[row.factory]=namespace[row.factory]}
const timer=ownerSetTimeout(()=>{throw Error('Owned provider factory Source fixture exceeded ten seconds')},10000);
let observed;
try{observed=await run({factories,all,models,wrappers:{withOpenCodeSessionHeader,cloudflareStreams,cloudflareClassifier,resolveCloudflareModel}})}finally{ownerClearTimeout(timer)}
if(observed.rows.filter(row=>row.case.startsWith('factory ')).length!==inventory.length||new Set(observed.rows.map(row=>row.case)).size!==observed.rows.length)throw Error('Observed factory inventory missing or repeated');
fs.writeFileSync(output,JSON.stringify({authority:'actual immutable ae7 provider factories, providers/all.ts and models.ts, with owned callback inputs only',sourceHead:'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d',actualNode:{version:process.version,executable:process.execPath},factoryCount:inventory.length,cases:observed.rows.length,rows:observed.rows,rawFunctions:observed.rawFunctions},null,2),{flag:'wx'});

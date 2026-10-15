// Actual immutable Source modules. Inventory contains names/paths, never results.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {setTimeout as ownerSetTimeout,clearTimeout as ownerClearTimeout} from 'node:timers';
delete process.env.PI_PACKAGE_DIR;
if(Object.hasOwn(process.env,'PI_PACKAGE_DIR'))throw Error('Default Source metadata requires absent PI_PACKAGE_DIR');
const config=await import('file:///C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/coding-agent/src/config.ts');
const sourcePackage={version:config.VERSION,packageDir:config.getPackageDir(),packageJsonPath:config.getPackageJsonPath()};
if(sourcePackage.version!=='1.3.0'||path.resolve(sourcePackage.packageDir)!==path.resolve('C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/coding-agent'))throw Error('Actual latest Source default package role mismatch');
const models=await import('file:///C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/ai/src/models.ts');
const all=await import('file:///C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/ai/src/providers/all.ts');
const {withOpenCodeSessionHeader}=await import('file:///C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/ai/src/providers/opencode-headers.ts');
const {cloudflareStreams,cloudflareClassifier,resolveCloudflareModel}=await import('file:///C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/ai/src/providers/cloudflare-stream.ts');
const {personalizeOpenRouterCatalog}=await import('file:///C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/ai/src/providers/openrouter.ts');
const {openRouterCost}=await import('file:///C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/ai/src/providers/openrouter-api.ts');
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
const apiRoot='file:///C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/ai/src/api/';
const apiDefinitions=[['anthropicMessagesApi','anthropic-messages'],['openAICompletionsApi','openai-completions'],['openAIResponsesApi','openai-responses'],['openAICodexResponsesApi','openai-codex-responses'],['azureOpenAIResponsesApi','azure-openai-responses'],['googleGenerativeAIApi','google-generative-ai'],['googleVertexApi','google-vertex'],['mistralConversationsApi','mistral-conversations'],['bedrockConverseStreamApi','bedrock-converse-stream'],['piMessagesApi','pi-messages'],['openAIDecisionsApi','openai-decisions'],['typesafeSystemOneApi','typesafe-system-one'],['cloudflareWorkersAISystemOneApi','cloudflare-workers-ai-system-one'],['openrouterImagesApi','openrouter-images']];
const apis={};for(const [name,file] of apiDefinitions){const namespace=await import(apiRoot+file+'.lazy.ts');if(typeof namespace[name]!=='function')throw Error('Original API export missing '+name);apis[name]=namespace[name]}
const timer=ownerSetTimeout(()=>{throw Error('Owned provider factory Source fixture exceeded ten seconds')},10000);
let observed;
try{observed=await run({factories,all,models,apis,wrappers:{withOpenCodeSessionHeader,cloudflareStreams,cloudflareClassifier,resolveCloudflareModel},helpers:{personalizeOpenRouterCatalog,openRouterCost}})}finally{ownerClearTimeout(timer)}
if(observed.rows.filter(row=>row.case.startsWith('factory ')).length!==inventory.length||new Set(observed.rows.map(row=>row.case)).size!==observed.rows.length)throw Error('Observed factory inventory missing or repeated');
fs.writeFileSync(output,JSON.stringify({authority:'actual immutable latest4954 provider factories, providers/all.ts and models.ts, with owned callback inputs only',sourceHead:'4954d760504c11df9b2cbdc040346107b6a8153d',actualNode:{version:process.version,executable:process.execPath},sourcePackage,packageOverrideAbsent:!Object.hasOwn(process.env,'PI_PACKAGE_DIR'),factoryCount:inventory.length,cases:observed.rows.length,rows:observed.rows,rawFunctions:observed.rawFunctions},null,2),{flag:'wx'});

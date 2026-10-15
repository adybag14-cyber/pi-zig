import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {dirname,resolve} from 'node:path';
const sourceRoot='C:/Users/adyba/pi-upstream-source-4954d76-20261015';
const core=sourceRoot+'/packages/coding-agent/src/core/';
// Original exports are imported intact. There is no class/body substitution,
// prototype patch, fake Models namespace, or dependency hook in the oracle.
const sdk=await import(pathToFileURL(core+'sdk.ts'));
const {AgentSession}=await import(pathToFileURL(core+'agent-session.ts'));
const {SessionManager}=await import(pathToFileURL(core+'session-manager.ts'));
const {SettingsManager}=await import(pathToFileURL(core+'settings-manager.ts'));
const {DefaultResourceLoader}=await import(pathToFileURL(core+'resource-loader.ts'));
const {ModelRuntime}=await import(pathToFileURL(core+'model-runtime.ts'));
const output=resolve(process.argv[2]),inputPath=resolve(process.argv[3]);
const fixtureCwd=resolve(dirname(output),'sandbox').replaceAll('\\','/');
mkdirSync(fixtureCwd,{recursive:true});
globalThis.factoryAPI={...sdk,AgentSession,SessionManager,SettingsManager,DefaultResourceLoader,ModelRuntime,fixtureCwd};
const input=readFileSync(inputPath);
let settleTimer;
try{await Promise.race([import('data:text/javascript,'+encodeURIComponent(input.toString('utf8'))),new Promise((_,reject)=>{settleTimer=setTimeout(()=>reject(Error('Factory27 10s settle deadline')),10000)})]);}finally{clearTimeout(settleTimer);}
if(factoryRows.length!==27)throw Error('Expected27 genuine factory cases');
const expectedErrors=new Set(['mixed-tools-error','pattern-modifier-error','raw-options-getter-rejection','null-options-rejection','services-raw-loader-rejection']);
for(const row of factoryRows){if(Boolean(row.error)!==expectedErrors.has(row.name))throw Error('Unexpected Source fixture outcome '+JSON.stringify(row));if(row.name==='raw-options-getter-rejection'&&!row.error.raw)throw Error('Raw reason identity was replaced');}
writeFileSync(output,JSON.stringify({sourceHead:'4954d760504c11df9b2cbdc040346107b6a8153d',inputSha256:createHash('sha256').update(input).digest('hex'),cases:factoryRows.length,scope:'Original actual SDK factory/services/fromServices/lifecycle exports, actual full Models and loader classes, caller-owned native provider and credentials without provider network requests. Real default runtime/settings/loader/manager paths, model/thinking restore, selection, tools, callbacks, raw reasons and getter order. No native or whole factory qualification inferred from Source observation.',rows:factoryRows},null,2));

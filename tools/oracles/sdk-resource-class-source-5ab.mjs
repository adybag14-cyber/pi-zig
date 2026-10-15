import {readFileSync, writeFileSync, realpathSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';

// The owner prepares and freezes every fixture file before this Source process.
// This driver is an oracle control, never a product host or native substitute.
const sourceRoot='C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015';
const core=pathToFileURL(sourceRoot+'/packages/coding-agent/src/core/').href;
const {DefaultResourceLoader}=await import(core+'resource-loader.ts');
const {SettingsManager}=await import(core+'settings-manager.ts');
globalThis.resourceClassDeps={DefaultResourceLoader,SettingsManager};
globalThis.resourceClassFixtureRoot=realpathSync(process.argv[4]);
const input=readFileSync(process.argv[3]);
await import('data:text/javascript,'+encodeURIComponent(input.toString('utf8')));
if(resourceClassRows.filter(row=>row.case.startsWith('actual-reload-discovery:')).length!==6)throw Error('All six actual package/default reload paths must execute');
if(!resourceClassRows.some(row=>row.case==='class-metadata'))throw Error('Actual class reflection was not captured');
writeFileSync(process.argv[2],JSON.stringify({sourceHead:'5ab7fe74c400097b386662205cd93900695b8a71',inputSha256:createHash('sha256').update(input).digest('hex'),cases:resourceClassRows.length,scope:'Actual DefaultResourceLoader class reflection, constructor/getter/path/source-info behavior, raw callback exceptions and package/default/trust discovery through genuine SettingsManager, DefaultPackageManager, extension loader and resource parsers. Native agreement is a separate qualification.',rows:resourceClassRows},null,2));

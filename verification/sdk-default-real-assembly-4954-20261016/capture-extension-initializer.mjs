// Prepared genuine Source controls. Run only under Root's sealed LIGHT slot.
import {readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
const root=fileURLToPath(new URL('../../',import.meta.url));
const source='C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/coding-agent/src/';
const pins={'core/extensions/loader.ts':'0177db97c7e35ea39cdab53124c04dbf6e045ac379670bcae0b4e1269002eb3a','core/source-info.ts':'52648af6e9bb29858ece4eaeccedd960c5de8a0ac4ec25c0ee851ff00de27f5c'};
for(const[path,sha]of Object.entries(pins))if(createHash('sha256').update(await readFile(source+path)).digest('hex')!==sha)throw Error('Original Source drift: '+path);
const output=process.argv[2];const fixture=process.argv[3];if(!output||!fixture)throw Error('Explicit new output and owned fixture required');
const packageRoot=resolve(source,'..');if(resolve(process.env.PI_PACKAGE_DIR??'')!==packageRoot)throw Error('Actual Source package must be explicit');
const input=resolve(root,'src/extensions/fixtures/sdk-extension-initializer-4954.input.mjs');const bytes=await readFile(input);
try{
  globalThis.ActualExtensionInitializer={loader:await import(pathToFileURL(source+'core/extensions/loader.ts').href),eventBus:await import(pathToFileURL(source+'core/event-bus.ts').href),sourceInfo:await import(pathToFileURL(source+'core/source-info.ts').href)};
  globalThis.ActualExtensionFixtureDir=resolve(fixture);
  await import(pathToFileURL(input).href);
  const rows=globalThis.ActualExtensionInitializerRows;if(!Array.isArray(rows)||rows.length!==34)throw Error('Initializer34 corpus incomplete: '+rows?.length);
  await writeFile(output,JSON.stringify({authority:'4954d760504c11df9b2cbdc040346107b6a8153d',packageRootOverride:packageRoot,inputSha256:createHash('sha256').update(bytes).digest('hex'),modules:pins,cases:rows.length,rows},null,2)+'\n',{flag:'wx'});
}finally{delete globalThis.ActualExtensionInitializer;delete globalThis.ActualExtensionFixtureDir;delete globalThis.ActualExtensionInitializerRows}

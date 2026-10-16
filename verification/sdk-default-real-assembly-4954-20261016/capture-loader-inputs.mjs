// One bounded owned Node process for genuine original initializer34+jiti14.
// No expected fixture is produced here. Controls and physical effects retained.
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
const output=process.argv[2];if(!output)throw Error('New output path required');
const fixture=output+'.physical-files';
const initialOutput=output+'.initializer.json',freshOutput=output+'.fresh-root.json';
process.argv[2]=initialOutput;process.argv[3]=fixture;
await import('./capture-extension-initializer.mjs');
process.argv[2]=freshOutput;process.argv[3]=fixture;
await import('./capture-jiti-fresh-root.mjs');
const initial=JSON.parse(await readFile(initialOutput)),fresh=JSON.parse(await readFile(freshOutput));
if(initial.cases!==34||fresh.cases!==14)throw Error('Actual component corpora incomplete');
const source='C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/coding-agent';
const packageBytes=await readFile(resolve(source,'package.json'));const pkg=JSON.parse(packageBytes);
const typeboxBytes=await readFile('C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/typebox/package.json');const typeboxSha=createHash('sha256').update(typeboxBytes).digest('hex');
if(pkg.version!=='1.3.0'||JSON.parse(typeboxBytes).version!=='1.3.27'||typeboxSha!=='c59ddfd977ce941f1e8ee8b0a0b14396c332fa27cc5fa6fa165227ffd5a3992f')throw Error('Actual package metadata drift');
const rows=[...initial.rows,...fresh.rows];
const controls={};for(const name of ['capture-extension-initializer.mjs','capture-jiti-fresh-root.mjs','capture-loader-inputs.mjs'])controls[name]=createHash('sha256').update(await readFile(new URL(name,import.meta.url))).digest('hex');
await writeFile(output,JSON.stringify({authority:initial.authority,packageRootOverride:source,packageSha256:createHash('sha256').update(packageBytes).digest('hex'),packageVersion:pkg.version,typeboxVersion:'1.3.27',typeboxPackageSha256:typeboxSha,inputSha256:initial.inputSha256,jitiVersion:fresh.jitiVersion,jitiPackageSha256:fresh.jitiPackageSha256,controls,modules:initial.modules,cases:48,rows,physical:fresh.physical,physicalFinal:fresh.physicalFinal,originalOutputs:{initializer:initialOutput,freshRoot:freshOutput}},null,2)+'\n',{flag:'wx'});

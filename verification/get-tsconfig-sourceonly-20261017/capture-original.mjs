// Prepared, unrun. Root's owned-process supervisor and exact source/runtime seals
// must admit execution. This program never substitutes a parser or fake fs.
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
const [entry,rawRoot,output]=process.argv.slice(2);
if(!entry||!rawRoot||!output||!path.isAbsolute(entry)||!path.isAbsolute(rawRoot)||!path.isAbsolute(output))throw Error('Exact absolute package entry, new physical root and new output required');
const root=path.resolve(rawRoot);
if(fs.existsSync(root)||fs.existsSync(output))throw Error('Original evidence destinations must be absent');
const sha256=file=>createHash('sha256').update(fs.readFileSync(file)).digest('hex').toUpperCase();
const acceptedEntries=new Set(['3BCCE3DE2DEF9C607EF6B02ED523653FF098C4FDCA268AB16C0DAE59B269759E','2565F23AABA3DA531BB08C5278556715C0C904CEF632D6C4C52B42230D2EA6C2']);
if(!acceptedEntries.has(sha256(entry)))throw Error('Exact published get-tsconfig4.14.0 entry required');
const mapsEntry=createRequire(entry).resolve('resolve-pkg-maps');
if(sha256(mapsEntry)!=='DC0FFABA25E180745BB1CE1622BE094BBC97D07DC275C52413EB546580D9FF49'||sha256(path.join(path.dirname(mapsEntry),'index.mjs'))!=='5472EB24AFA47C614E7EDACCB0CCB4C6259F897D875C27057EE00B7C2CDC3672')throw Error('Exact resolve-pkg-maps1.0.0 CJS and ESM entries required');
const subject=await import(pathToFileURL(entry).href);
const here=path.dirname(fileURLToPath(import.meta.url));
const fixtureFile=path.resolve(here,'../../src/extensions/fixtures/get-tsconfig-4.14.0-files.input.json');
const fixtures=JSON.parse(fs.readFileSync(fixtureFile,'utf8'));
fs.mkdirSync(root);
for(const [relative,text]of Object.entries(fixtures)){const destination=path.resolve(root,relative);if(!destination.startsWith(root+path.sep))throw Error('Fixture escapes physical root');fs.mkdirSync(path.dirname(destination),{recursive:true});fs.writeFileSync(destination,text)}
globalThis.nativeTsconfigSubject=subject;globalThis.nativeTsconfigRoot=root;
await import(pathToFileURL(path.resolve(here,'../../src/extensions/fixtures/get-tsconfig-4.14.0.input.mjs')).href);
fs.writeFileSync(output,JSON.stringify(globalThis.nativeTsconfigObservation,null,2)+'\n',{flag:'wx'});

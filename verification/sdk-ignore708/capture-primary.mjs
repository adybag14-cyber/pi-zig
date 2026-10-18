// UNRUN original-package caller. Root-owned bounded reference capture required.
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {runIgnore708ConsumedCases} from './ignore-consumed-callers.mjs';
const configPath=process.argv[2];
if(!configPath)throw Error('Explicit owned Root config required');
const config=JSON.parse(readFileSync(configPath,'utf8'));
if(config.authorized!==true||config.scope!=='sdk-private-ignore708-primary')throw Error('Explicit original ignore708 Root scope required');
const root=config.container;
if(typeof root!=='string')throw Error('Explicit Root-validated physical container required');
const layout=JSON.parse(readFileSync(join(root,'.pi-zig-workspace.json'),'utf8'));
if(layout.runtime_status!=='original_manifest_verified_current_bytes'||layout.runtime_verification_receipt_sha256!=='EFEC9629751FA119BE0B311D206A7F8A10A5A9E31213482FBBF647C6B6C11CF0')throw Error('Accepted original31064 byte authority required');
const pins=JSON.parse(readFileSync(new URL('./primary-provenance.json',import.meta.url),'utf8'));
for(const pin of pins.primary_sources){const actual=createHash('sha256').update(readFileSync(join(root,layout.runtime,pin.relative))).digest('hex').toUpperCase();if(actual!==pin.sha256)throw Error('Original ignore708 package member changed');}
const packageRoot=join(root,layout.runtime,'node_modules/ignore');
const original=await import(pathToFileURL(join(packageRoot,'index.js')).href);
const rows=runIgnore708ConsumedCases(original.default);
const ids=JSON.parse(readFileSync(new URL('./authored-case-ids.json',import.meta.url),'utf8'));
if(rows.length!==246||rows.some((row,index)=>row.id!==ids[index]))throw Error('Original authored ordered246 cases required');
process.stdout.write(JSON.stringify({scope:'genuine-installed-ignore708-consumed-surface',version:JSON.parse(readFileSync(join(packageRoot,'package.json'),'utf8')).version,platform:process.platform,observations:rows})+'\n');

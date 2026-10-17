// Genuine primary caller. UNRUN: bounded owned Node/cleared-env grant required.
import {readFileSync,realpathSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {runChalkConsumedCases} from './chalk-consumed-callers.mjs';
const configPath=process.argv[2];
if(!configPath)throw new Error('Explicit owned config path required');
const config=JSON.parse(readFileSync(configPath,'utf8'));
if(config.scope!=='sdk-private-chalk6-primary'||config.authorized!==true||config.caseId!=='consumed-style-corpus')throw new Error('Explicit Chalk-only Root config required');
const root=realpathSync(config.container),layout=JSON.parse(readFileSync(join(root,'.pi-zig-workspace.json'),'utf8'));
if(layout.runtime_status!=='original_manifest_verified_current_bytes'||layout.runtime_verification_receipt_sha256!=='EFEC9629751FA119BE0B311D206A7F8A10A5A9E31213482FBBF647C6B6C11CF0')throw new Error('Accepted original runtime authority required');
const primary=join(root,layout.runtime,'node_modules/chalk');
const pins=JSON.parse(readFileSync(new URL('./primary-provenance.json',import.meta.url),'utf8'));
for(const pin of pins.primary_sources){if(!pin.original_manifest_exact)continue;const actual=createHash('sha256').update(readFileSync(join(root,layout.runtime,pin.relative))).digest('hex').toUpperCase();if(actual!==pin.sha256)throw new Error('Exact original Chalk source changed');}
const source=await import(pathToFileURL(join(primary,'source/index.js')).href);
const observations=runChalkConsumedCases(source.default);
if(observations.length!==86||new Set(observations.map(row=>row.id)).size!==86)throw new Error('Original authored 86 unique observations required');
process.stdout.write(JSON.stringify({scope:'genuine-installed-chalk6-consumed-surface',version:JSON.parse(readFileSync(join(primary,'package.json'),'utf8')).version,defaultLevel:source.default.level,observations})+'\n');

// Prepared genuine reference driver; execute only after a new Root grant.
import {readFileSync,writeFileSync,existsSync,realpathSync} from 'node:fs';
import {dirname,join,resolve,sep} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {runRetry698ClassifierCases} from './retry-698a-classifier.input.mjs';
let container=dirname(fileURLToPath(import.meta.url));
while(!existsSync(join(container,'.pi-zig-workspace.json'))){const parent=dirname(container);if(parent===container)throw Error('Contained workspace required');container=parent;}
const layout=JSON.parse(readFileSync(join(container,'.pi-zig-workspace.json')));
const source=realpathSync(process.argv[2]),output=resolve(process.argv[3]);
const required=resolve(container,layout.upstream,'snapshots/698a2d23-20261016');
if(source!==required||!output.startsWith(resolve(container,layout.evidence)+sep)||existsSync(output))throw Error('Explicit fresh contained source/output required');
if(process.version!=='v24.14.0'||process.env.PI_PACKAGE_DIR)throw Error('Pinned actual Node reference required');
const provenance=JSON.parse(readFileSync(new URL('./provenance.json',import.meta.url)));
const modulePath=join(source,'packages/ai/src/utils/retry.ts');
const sha=path=>createHash('sha256').update(readFileSync(path)).digest('hex').toUpperCase();
if(sha(modulePath)!==provenance.files.find(row=>row.path==='packages/ai/src/utils/retry.ts').sha256)throw Error('Exact retained698 Source classifier changed');
const {isRetryableAssistantError}=await import(pathToFileURL(modulePath));
const rows=runRetry698ClassifierCases(isRetryableAssistantError);
writeFileSync(output,JSON.stringify({sourceHead:provenance.source_head,sourceTree:provenance.source_tree,actualNode:{version:process.version,pid:process.pid,execPath:process.execPath},moduleSha256:sha(modulePath),callerSha256:sha(fileURLToPath(new URL('./retry-698a-classifier.input.mjs',import.meta.url))),cases:rows.length,rows,nativeQualified:false},null,2));

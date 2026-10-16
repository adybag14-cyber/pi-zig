// Prepared original Node control only. Never an implementation host for Pi.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
if(process.version!=='v24.14.0')throw new Error(`Pinned Node v24.14.0 required, got ${process.version}`);
const cases=['constructor-metadata','write-sync-order','write-async-backpressure','cork-writev','final-finish-close','destroy-once','duplex-half-open','readable-read-unshift','pipe-pause-drain-unpipe','decoder-utf8-carry-bom','decoder-utf16-base64','from-sync-jsonl-original','from-async-values-order','from-async-iterator-close','from-web-real-reader','from-web-cancel','passthrough-readable-backpressure','pipeline-node-and-end-false','finished-premature-close','original-child-exit-tail'];
const caseName=process.argv[2];if(!cases.includes(caseName))throw new Error('Exactly one original Source20 case is required');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const fixtures=path.join(root,'src','extensions','fixtures');
globalThis.caseName=caseName;
globalThis.originalJsonl=await import(pathToFileURL(path.join(fixtures,'node-stream-classic-source','jsonl.ts')).href);
globalThis.originalChildWait=await import(pathToFileURL(path.join(fixtures,'node-stream-classic-source','wait-for-child-process.excerpt.ts')).href);
const input=fs.readFileSync(path.join(fixtures,'node-stream-classic-node24.input.txt'),'utf8');
await import(`data:text/javascript;base64,${Buffer.from(input).toString('base64')}`);
if(!globalThis.packet||packet.case!==caseName)throw new Error('Original packet did not terminally publish');
process.stdout.write(`${JSON.stringify({nodeVersion:process.version,platform:process.platform,case:caseName,packet})}\n`);

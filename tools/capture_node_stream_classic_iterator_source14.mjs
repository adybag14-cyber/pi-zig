// Original Node control only; never a classic stream host implementation.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
if(process.version!=='v24.14.0')throw new Error(`Pinned Node v24.14.0 required, got ${process.version}`);
const cases=['iterator-genuine-brand','iterator-lazy-pending-eof','iterator-for-await-natural','iterator-break-default','iterator-return-false-resume','iterator-options-live-finally','iterator-yield-thenable','iterator-yield-rejection','iterator-throw-identity','iterator-pending-stream-error','iterator-return-queued-behind-read','iterator-child-exit-is-not-eof','pipeline-node-real-completion-backpressure','pipeline-node-error-closes-source-iterator'];
const caseName=process.argv[2];if(!cases.includes(caseName))throw new Error('Exactly one original Source14 case is required');
globalThis.caseName=caseName;
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const input=fs.readFileSync(path.join(root,'src','extensions','fixtures','node-stream-classic-iterator-node24.input.txt'),'utf8');
await import(`data:text/javascript;base64,${Buffer.from(input).toString('base64')}`);
if(!globalThis.packet||packet.case!==caseName)throw new Error('Original packet did not terminally publish');
process.stdout.write(`${JSON.stringify({nodeVersion:process.version,platform:process.platform,case:caseName,packet})}\n`);

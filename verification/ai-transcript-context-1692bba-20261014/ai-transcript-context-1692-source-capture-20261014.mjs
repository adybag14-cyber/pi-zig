import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const {createInitialSystemMessage,normalizeContext}=await import('file:///C:/Users/adyba/pi-upstream-source-1692bba-20261014/packages/ai/src/utils/transcript.ts');
globalThis.transcriptContextAPI={createInitialSystemMessage,normalizeContext};
const input=readFileSync(process.argv[3]);
await import('data:text/javascript,'+encodeURIComponent(input.toString('utf8')));
if(transcriptContextRows.length!==20)throw Error('All20 original transcript observations required');
writeFileSync(process.argv[2],JSON.stringify({sourceHead:'1692bba6347a287ab0f3cb554a4430fafffc474b',inputSha256:createHash('sha256').update(input).digest('hex'),scope:'Actual unchanged original transcript.ts initial-system and normalizeContext exports; caller-owned values and restored public method override; no Source bodies replaced',cases:20,rows:transcriptContextRows},null,2));
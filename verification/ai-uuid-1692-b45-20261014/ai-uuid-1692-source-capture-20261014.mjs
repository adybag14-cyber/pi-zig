import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const {uuidv7}=await import('file:///C:/Users/adyba/pi-upstream-source-1692bba-20261014/packages/ai/src/utils/uuid.ts');
globalThis.uuidAPI=uuidv7;
const input=readFileSync(process.argv[3]);
await import('data:text/javascript,'+encodeURIComponent(input.toString('utf8')));
if(uuidRows.length!==26)throw Error('All26 original UUID observations required');
writeFileSync(process.argv[2],JSON.stringify({sourceHead:'1692bba6347a287ab0f3cb554a4430fafffc474b',inputSha256:createHash('sha256').update(input).digest('hex'),scope:'Actual unchanged original UUIDv7 module with caller-owned deterministic Date/crypto hooks; module timestamp and sequence preserved across every scenario',cases:26,rows:uuidRows},null,2));

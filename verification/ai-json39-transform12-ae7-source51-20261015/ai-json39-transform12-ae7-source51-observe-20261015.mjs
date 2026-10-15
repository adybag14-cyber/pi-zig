import { writeFileSync,readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
const base='C:/Users/adyba/pi-zig-update-evidence-20261003/';
const callers=['ai-json-parse-ae7-caller-20261015.mjs','ai-json-delegate-ae7-caller-20261015.mjs','ai-transform-thinking-ae7-caller12-20261015.mjs'];
const sections=[];
for(const [index,caller] of callers.entries()){
 const path=base+caller,rows=(await import('file:///'+path)).default;
 if(!Array.isArray(rows)||rows.length!==[33,6,12][index])throw Error('Mandatory genuine caller count mismatch '+caller);
 sections.push({caller,sha256:createHash('sha256').update(readFileSync(path)).digest('hex'),count:rows.length,rows});
}
writeFileSync(process.argv[2],JSON.stringify({sourceHead:'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d',runtime:process.version,actualNode:{execPath:process.execPath,pid:process.pid},count:51,scope:'Actual unmodified latest-ae7 JSON33 + delegate6 original caller inputs and targeted thinking-DROP12. Historical b06 callers only changed import root. No native implementation, normalized errors, or provider execution.',sections},null,2));

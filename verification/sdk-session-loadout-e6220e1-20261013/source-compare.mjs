// Compare two genuine captures; only seven bounded Date.now observations vary.
import{readFileSync,writeFileSync}from'node:fs';
import{createHash}from'node:crypto';
const first=JSON.parse(readFileSync(process.argv[2])),second=JSON.parse(readFileSync(process.argv[3]));
const scenarios=new Set(['prepare-first','prepare-remove','prepare-explicit-messages','prepare-forced','prepare-hidden','prepare-options-accessors','prepare-current-replay']);
if(first.source!==second.source||first.platform!==second.platform||first.callerInputSha256!==second.callerInputSha256||first.packageDirectory!==second.packageDirectory||first.factories!==34||second.factories!==34)throw Error('Source capture identities changed');
let count=0;const slots=[];
for(let i=0;i<first.raw.rows.length;i++){
 const a=first.raw.rows[i],b=second.raw.rows[i];
 if(a.scenario!==b.scenario)throw Error('Source case identity changed');
 if(!a.result?.patch)continue;
 if(!scenarios.has(a.scenario)||!b.result?.patch)throw Error('Unexpected timestamp slot');
 for(const [capture,row]of [[first,a],[second,b]]){
  const value=row.result.patch.timestamp;
  if(!Number.isSafeInteger(value)||value<capture.timeBounds.began||value>capture.timeBounds.ended)throw Error('Source timestamp outside actual capture bounds');
 }
 slots.push({scenario:a.scenario,first:a.result.patch.timestamp,second:b.result.patch.timestamp});
 a.result.patch.timestamp=null;b.result.patch.timestamp=null;count++;
}
if(count!==7||JSON.stringify(first.raw)!==JSON.stringify(second.raw))throw Error('Stable Source55 output changed');
const fresh=JSON.parse(readFileSync(process.argv[3]));
const fixture={source:fresh.source,scope:'Original latest AgentSession factory Source55; platform-specific genuine capture.',sourceMode:fresh.sourceMode,sourceTimeBounds:fresh.timeBounds,sourceFactories:fresh.factories,...fresh.raw};
writeFileSync(process.argv[4],JSON.stringify(fixture,null,2)+'\n');
console.log(JSON.stringify({status:'Source55_double_capture_exact',platform:fresh.platform,cases:55,factories:34,timestampSlots:slots,fixtureSha256:createHash('sha256').update(readFileSync(process.argv[4])).digest('hex')}));

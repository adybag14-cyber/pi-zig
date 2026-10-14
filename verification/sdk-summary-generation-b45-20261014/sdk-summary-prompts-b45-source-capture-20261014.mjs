import{readFileSync,writeFileSync}from'node:fs';import{createHash}from'node:crypto';
const base='file:///C:/Users/adyba/pi-upstream-source-b45e0eb-20261014/packages/coding-agent/src/core/compaction/';
const{generateSummaryWithUsage,compact}=await import(base+'compaction.ts'),{createFileOps}=await import(base+'utils.ts');
const input=readFileSync(process.argv[3]),plan=JSON.parse(input);if(plan.cases.join(',')!=='initial,update,turn-prefix')throw Error('Exact prompt plan required');
const model={id:'fixture',api:'summary-fixture',provider:'summary-fixture-provider',maxTokens:1000,reasoning:false},requests=[];
const stream=(m,c,o)=>{requests.push({modelSame:m===model,context:c,options:o});return{result(){return{role:'assistant',content:[{type:'text',text:'CAPTURE-SUMMARY'}],stopReason:'stop',usage:{input:1,output:1,cacheRead:0,cacheWrite:0,totalTokens:2,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}},timestamp:0};}};};
const old=Date.now;Date.now=()=>1000;
try{
 await generateSummaryWithUsage([],model,1000,'fixture',undefined,undefined,undefined,undefined,undefined,stream,undefined,undefined,undefined,'capture');
 await generateSummaryWithUsage([],model,1000,'fixture',undefined,undefined,undefined,'CAPTURE-PREVIOUS',undefined,stream,undefined,undefined,undefined,'capture');
 await compact({firstKeptEntryId:'kept',messagesToSummarize:[],turnPrefixMessages:[{role:'user',content:'CAPTURE-TURN',timestamp:0}],isSplitTurn:true,tokensBefore:1,previousSummary:undefined,fileOps:createFileOps(),settings:{reserveTokens:1000}},model,'fixture',undefined,undefined,undefined,undefined,stream,undefined,undefined,undefined,'capture');
}finally{Date.now=old;}
if(requests.length!==3||requests.some(r=>r.context.messages.length!==2||r.context.messages[0].role!=='system'||r.context.messages[1].role!=='user'))throw Error('Three actual normalized requests required');
function suffix(text,delimiter){const at=text.indexOf(delimiter);if(at<0||text.indexOf(delimiter,at+delimiter.length)!==-1)throw Error('Unique original prompt delimiter required');return text.slice(at+delimiter.length);}
const prompts={system:requests[0].context.messages[0].content,initial:suffix(requests[0].context.messages[1].content[0].text,'</conversation>\n\n'),update:suffix(requests[1].context.messages[1].content[0].text,'</previous-summary>\n\n'),turnPrefix:suffix(requests[2].context.messages[1].content[0].text,'# Instructions\n')};
if(requests.some(r=>r.context.messages[0].content!==prompts.system))throw Error('System prompt identity changed');
writeFileSync(process.argv[2],JSON.stringify({sourceHead:'b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb',inputSha256:createHash('sha256').update(input).digest('hex'),cases:3,scope:'Exact prompt strings observed through actual unchanged generation and compact call paths, supplied model stream and deterministic clock; no Source bodies read as executable substitutes',rows:requests,prompts},null,2));

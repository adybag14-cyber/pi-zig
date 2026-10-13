// Receipt verification only. This never replaces or executes a native probe.
import{readFileSync,writeFileSync}from'node:fs';
import{join,resolve}from'node:path';
import{createHash}from'node:crypto';
const evidence=resolve(process.argv[2]),output=resolve(process.argv[3]);
const read=path=>JSON.parse(readFileSync(path,'utf8').replace(/^\uFEFF/,''));
const sha=path=>createHash('sha256').update(readFileSync(path)).digest('hex');
const equal=(a,b,label)=>{if(JSON.stringify(a)!==JSON.stringify(b))throw Error(label);};
const modes={};let universe, frozenInputs;
for(const mode of ['debug','releasesafe']){
 const covered=[],ranges=[];let previous=0;
 for(let shard=0;shard<8;shard++){
  const base=join(evidence,`sdk-visual-preview-${mode}-${mode==='debug'?'final-strict-debug':'final-strict-rs'}-shard${shard}-of8-20261013`);
  const state=read(base+'.process.json'),post=read(base+'-posthash.json'),text=readFileSync(base+'.stderr.log','utf8');
  if(state.status!=='passed'||state.exit_code!==0||post.source_drift!==0||post.tool_drift!==0||!text.includes('11/11 tests passed')||!text.includes('156/156 steps succeeded'))throw Error('Incomplete native terminal gate '+base);
  const baseline=[...text.matchAll(/^EXHAUSTIVE_ALLOCATION_BASELINE sdk-tool-visual-preview total=(\d+)$/gm)];
  const range=[...text.matchAll(/^EXHAUSTIVE_ALLOCATION_RANGE sdk-tool-visual-preview (\d+)\/(\d+) range=\[(\d+),(\d+)\) total=(\d+)$/gm)];
  if(baseline.length!==1||range.length!==1)throw Error('Baseline/range cardinality changed');
  const inputs=read(base+'-source-before.json');frozenInputs??=inputs;equal(inputs,frozenInputs,'Full frozen source changed between partitions/modes');
  if(state.outer_seconds!==300||state.settle_seconds!==10)throw Error('Owner deadline profile changed');
  const total=Number(baseline[0][1]);universe??=total;if(total!==universe)throw Error('Allocation universe changed across shards or modes');
  const[index,count,start,end,declared]=range[0].slice(1).map(Number);
  equal([index,count,start,end,declared],[shard,8,Math.floor(total*shard/8),Math.floor(total*(shard+1)/8),total],'Partition is not the original exact range');
  if(start!==previous)throw Error('Range gap or overlap');previous=end;
  const begun=[...text.matchAll(/^EXHAUSTIVE_ALLOCATION_INDEX_BEGIN sdk-tool-visual-preview (\d+)$/gm)].map(m=>Number(m[1]));
  const done=[...text.matchAll(/^EXHAUSTIVE_ALLOCATION_INDEX_COMPLETE sdk-tool-visual-preview (\d+)$/gm)].map(m=>Number(m[1]));
  const expected=Array.from({length:end-start},(_,i)=>start+i);
  equal(begun,expected,'Original allocation begin indices missing or repeated');equal(done,expected,'Original allocation completion indices missing or repeated');
  const marker=`EXHAUSTIVE_ALLOCATION_COMPLETE sdk-tool-visual-preview ${shard}/8 range=[${start},${end}) total=${total}`;
  if(text.split(marker).length!==2)throw Error('Exact terminal range marker missing or repeated');
  covered.push(...done);ranges.push({shard,start,end,count:done.length,pid:state.pid,created_utc:state.created_utc,completed_utc:state.completed_utc,state_sha256:sha(base+'.process.json'),stderr_sha256:sha(base+'.stderr.log'),source_before_sha256:sha(base+'-source-before.json'),posthash_sha256:sha(base+'-posthash.json'),post});
 }
 equal(covered,Array.from({length:universe},(_,i)=>i),'Full original universe not covered exactly once');
 if(previous!==universe||new Set(covered).size!==universe)throw Error('Universe gap/duplicate');
 modes[mode]={status:'all8_terminal_complete',baseline_total:universe,indices_complete:covered.length,missing:0,duplicates:0,ranges};
}
const packet={status:'Windows_Debug_ReleaseSafe_Source23_visual_preview_GC_all_allocation_indices_qualified',source:'e6220e1316f86af818a0ccbfe1c09d7e918b41cf',same_Probe:true,full_Source23_and_metadata_per_trial:true,full_source_inputs_equal_across_all16:true,source_inputs:frozenInputs.length,product_repair:'native Text genuine hostOOM tagged at its callback boundary',caller_negative_repair:'unexpected exceptions rethrown unchanged; genuine Original23 rows remain exact',baseline_total:universe,modes,host_await_ms:10000,test_timeout_seconds:120,outer_seconds_each:300,backend:'default LLVM',j:1,public_activation:false,hosted_qualification:'pending; these are Windows local component receipts'};
writeFileSync(output,JSON.stringify(packet,null,2)+'\n');
console.log(JSON.stringify({status:packet.status,total_each_mode:universe,partitions_each_mode:8,missing:0,duplicates:0}));

// Pure static authoring over typed records captured by the ORIGINAL lowering.
// No authority evaluation, second AST lowering, generated-Zig parser or runtime.
import {checkContinuationStep,usesNativeName,callsNativeMember} from './outline-call-setup.mjs';
export const continuationModules=new Set(['type/engine/instantiate.mjs','type/engine/call/instantiate.mjs','type/engine/call/resolve_arguments.mjs']);
export const selectedContinuation=(file,name)=>continuationModules.has(file)||(file==='guard/guard.mjs'&&name==='ShiftLeft');
const uint=value=>Number.isSafeInteger(value)&&value>=0;
function structured(records,start=0,stops=new Set()){
 const block=[];let cursor=start;
 while(cursor<records.length){
  const record=records[cursor];if(stops.has(record.kind))return{block,cursor};cursor++;
  if(record.kind==='if'){
   const yes=structured(records,cursor,new Set(['else','endif']));cursor=yes.cursor;
   let no={block:[]};
   if(records[cursor]?.kind==='else'){no=structured(records,cursor+1,new Set(['endif']));cursor=no.cursor}
   if(records[cursor]?.kind!=='endif')throw Error('Unclosed typed conditional');cursor++;
   block.push({...record,yes:yes.block,no:no.block});
  }else if(record.kind==='try'){
   const finalizer=structured(records,cursor,new Set(['end_finally']));cursor=finalizer.cursor;
   if(records[cursor]?.kind!=='end_finally')throw Error('Unclosed typed finally');cursor++;
   block.push({...record,finalizer:finalizer.block});
  }else if(['else','endif','end_finally'].includes(record.kind))throw Error('Foreign typed control boundary');
  else if(record.kind!=='ignore')block.push(record);
 }
 return{block,cursor};
}
function admitCall(record,frame){
 if(record.owner!==frame.key||!uint(record.result)||record.result>=frame.base||typeof record.construct!=='boolean')throw Error('Continuation call owner/result invalid');
 const operand=text=>{const match=typeof text==='string'?text.match(/^native_values\[(0|[1-9]\d*)\]$/):null;return match&&uint(Number(match[1]))&&Number(match[1])<frame.base};
 if(!operand(record.callable)||!(operand(record.receiver)||record.receiver==='c.pi_js_undefined()'))throw Error('Continuation callee/receiver must be pre-evaluated original operands');
 const range=record.range;
 if(!range||range.owner!==frame.key||!uint(range.start)||!uint(range.count)||typeof range.empty!=='boolean')throw Error('Continuation argument owner invalid');
 if(range.empty){if(range.start!==0||range.count!==0||record.args!=='&.{}')throw Error('Continuation empty range invalid');return'native_values[0..0]'}
 if(!range.count||!uint(range.start+range.count)||range.start+range.count>frame.count||!frame.ranges.some(item=>item.start===range.start&&item.count===range.count))throw Error('Continuation argument range invalid');
 const expected=`native_values[__TYPEBOX_NATIVE_ARG_${frame.key}_${range.start}__..__TYPEBOX_NATIVE_ARG_${frame.key}_${range.start+range.count}__]`;
 if(record.args!==expected)throw Error('Continuation argument expression differs from typed range');
 return expected;
}
export function emitContinuations(functions,branches,tries,frames,{expectedCount=34}={}){
 const selected=functions.filter(f=>selectedContinuation(f.module.file,f.name));
 if(selected.length!==expectedCount)throw Error('Finite continuation callback census changed');
 const globals=[...functions.map(f=>`f_${f.id}`),...selected.map(f=>`typebox_plan_${f.id}`)],native=[],provenance=[];
 for(const f of selected){
  const frame=frames.get(`f${f.id}`);if(!frame||frame.base!==f.originalSlots||!uint(frame.base)||!uint(frame.count)||!uint(f.slots)||f.slots<frame.base+frame.count)throw Error('Continuation original owner frame missing');
  const steps=[],active=new Set();let calls=0,constructors=0;
  function add(body){const id=steps.length;steps.push(body);return id}
  const next=pc=>`return .{ .next = ${pc} };`;
  function completeBranch(value,target,after){return add(`native_values[${target}] = ${value};\n${next(after)}`)}
  function reference(kind,id,target,after,inFinally){
   const key=`${kind}_${id}`;if(active.has(key))throw Error('Cyclic original branch/try graph');active.add(key);
   const unit=(kind==='branch'?branches:tries)[id]?.unit;
   if(!unit||unit.owner!==frame.key)throw Error('Foreign branch/try owner in continuation');
   const entry=block(structured(unit.records).block,after,{target,inFinally});active.delete(key);return entry;
  }
  function block(records,after,{target=null,inFinally=false}={}){
   let following=after;
   for(let index=records.length-1;index>=0;index--){const record=records[index];
    switch(record.kind){
     case'emit':{
      // Native locals/defaults/iterators would need typed heap fields; they
      // are explicitly unsupported in this finite source selection.
      if(/[{}]/.test(record.text.replace(/"(?:\\.|[^"\\])*"/g,'')))throw Error('Untyped native control in continuation');
      if(['return','runBranch'].some(name=>usesNativeName(record.text,name))||['invoke','invokeSpread','construct'].some(member=>callsNativeMember(record.text,'rt',member)))throw Error('Unrecorded call/control in continuation');
      following=add(`${record.text}\n${next(following)}`);break;
     }
     case'call':{const args=admitCall(record,frame);calls++;if(record.construct)constructors++;
      following=add(`return .{ .call = .{ .function = ${record.callable}, .receiver = ${record.receiver}, .args = ${args}, .result = ${record.result}, .next = ${following}, .construct = ${record.construct} } };`);break;
     }
     case'branch_result':if(!uint(record.result)||record.result>=frame.base)throw Error('Branch result outside original slots');else following=reference('branch',record.id,record.result,following,inFinally);break;
     case'branch_jump':if(target===null)throw Error('Branch jump outside expression');else following=reference('branch',record.id,target,after,inFinally);break;
     case'branch_value':if(target===null)throw Error('Branch value outside expression');else following=completeBranch(record.value,target,after);break;
     case'returned':following=add(`return .{ .returned = ${record.value} };`);break;
     case'thrown':following=add(`return .{ .thrown = ${record.value} };`);break;
     case'if':{const yes=block(record.yes,following,{target,inFinally}),no=block(record.no,following,{target,inFinally});following=add(`return .{ .next = if (${record.test}) ${yes} else ${no} };`);break}
     case'try':{
      if(inFinally||f.id!==662||target!==null)throw Error('Unsupported nested or foreign continuation finally');
      const finish=add('return .finish_finally;'),handler=block(record.finalizer,finish,{inFinally:true});
      const leave=add(`return .{ .leave_try = ${following} };`),body=reference('try',record.id,null,leave,false);
      following=add(`return .{ .enter_finally = .{ .handler = ${handler}, .next = ${body} } };`);break;
     }
     default:throw Error(`Unadmitted typed continuation operation ${record.kind}`);
    }
   }return following;
  }
  const end=add('return .{ .returned = c.pi_js_undefined() };');
  const body=block(structured(f.unit.records).block,end);
  const entry=add(`a.env = try rt.environment(s, roots[0]);\n${next(body)}`);
  for(let id=0;id<steps.length;id++){
   const text=steps[id],needs=checkContinuationStep(text,frame.key,frames,globals);
   let aliases='';
   if(usesNativeName(text,'s'))aliases+='const s = &a.scope;\n';
   if(needs.engine)aliases+='const engine = a.scope.engine;\n';
   if(needs.env)aliases+='const env = a.env;\n';
   if(needs.native_values)aliases+='const native_values = a.values;\n';
   if(needs.args)aliases+='const args = a.args;\n';
   if(needs.roots||needs.receiver&&f.arrow)aliases+='const roots = a.roots;\n';
   if(needs.receiver)aliases+=`const receiver = ${f.arrow?'roots[1]':'a.receiver'};\n`;
   native.push(`noinline fn typebox_pc_${f.id}_${id}(a: *rt.Continuation.Activation) anyerror!rt.Continuation.Action {\n${usesNativeName(text,'a')||aliases?'':'_ = a;\n'}${aliases}${text}\n}\n`);
  }
  native.push(`const typebox_steps_${f.id} = [_]*const fn (*rt.Continuation.Activation) anyerror!rt.Continuation.Action { ${steps.map((_,id)=>`typebox_pc_${f.id}_${id}`).join(', ')} };\nconst typebox_plan_${f.id}: rt.Continuation.Plan = .{ .source_callback = f_${f.id}, .slots = ${f.slots}, .entry = ${entry}, .steps = &typebox_steps_${f.id} };\n`);
  provenance.push({nativeCallback:`f_${f.id}`,owner:frame.key,source:f.module.file,start:f.node.start,end:f.node.end,originalOperandSlots:f.originalSlots,allocatedSlots:f.slots,entry,steps:steps.length,actualCallSites:calls,constructCallSites:constructors,originalFlags:{receiver:f.usesReceiver,args:f.usesArgs,env:f.usesEnv,arrow:f.arrow},legacyCallbackBodyExecutedByPlan:false});
 }
 return{native:native.join(''),provenance};
}

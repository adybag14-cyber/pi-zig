// Static authoring postpass only. Never imported by a production runtime.
const abiNames=new Set(['s','env','receiver','native_values','engine','args','roots']);
const keywords=new Set(['try','if','else','while','for','const','var','return','break','continue','defer','errdefer','catch','orelse','and','or','true','false','null','undefined','unreachable','void','anyerror','usize','isize','_']);
function tokens(text){
 const out=[];let index=0;
 while(index<text.length){
  const char=text[index];
  if(/\s/.test(char)){index++;continue}
  if(char==='"'||char==="'"){const quote=char;index++;let closed=false;while(index<text.length){if(text[index]==='\\'){index+=2;continue}if(text[index++]===quote){closed=true;break}}if(!closed)throw Error('Unclosed generated native literal');continue}
  if(text.startsWith('//',index)){const end=text.indexOf('\n',index);index=end<0?text.length:end;continue}
  if(text.startsWith('/*',index)){const end=text.indexOf('*/',index+2);if(end<0)throw Error('Unclosed generated native comment');index=end+2;continue}
  if(text.startsWith('..',index)){out.push({kind:'punct',text:'..'});index+=2;continue}
  if(/[0-9]/.test(char)||(char==='.'&&/[0-9]/.test(text[index+1]??''))){const number=text.slice(index).match(/^(?:0[xX][0-9a-fA-F_]+(?:\.(?!\.)[0-9a-fA-F_]*)?(?:[pP][+-]?[0-9_]+)?|[0-9_]+(?:\.(?!\.)[0-9_]*)?(?:[eE][+-]?[0-9_]+)?|\.[0-9_]+(?:[eE][+-]?[0-9_]+)?)/);if(!number)throw Error('Invalid generated numeric literal');index+=number[0].length;continue}
  if(/[A-Za-z_]/.test(char)){const match=text.slice(index).match(/^[A-Za-z_][A-Za-z0-9_]*/)[0];out.push({kind:'name',text:match});index+=match.length;continue}
  out.push({kind:'punct',text:char});index++;
 }
 return out;
}
export function usesNativeName(body,name){const scanned=tokens(body);return scanned.some((token,index)=>token.kind==='name'&&token.text===name&&scanned[index-1]?.text!=='.'&&scanned[index-1]?.text!=='@')}
export function callsNativeMember(body,owner,member){const scanned=tokens(body);return scanned.some((token,index)=>token.text===owner&&scanned[index+1]?.text==='.'&&scanned[index+2]?.text===member&&scanned[index+3]?.text==='(')}
function closure(body,unit,globals,frames){
 const scanned=tokens(body),declared=new Set(),referenced=new Set();
 for(let index=0;index<scanned.length;index++){
  const token=scanned[index];
  if(token.kind!=='name')continue;
  if(token.text==='const'||token.text==='var'){
   const next=scanned[index+1];if(next?.kind!=='name')throw Error('Unsupported generated native declaration in setup region');declared.add(next.text);continue;
  }
  if(scanned[index-1]?.text==='.'||scanned[index-1]?.text==='@'||keywords.has(token.text)||/^[uif]\d+$/.test(token.text))continue;
  referenced.add(token.text);
 }
 const needs={s:false,env:false,receiver:false,native_values:false,engine:false,args:false,roots:false};
 for(const name of referenced){
  if(declared.has(name)||globals.has(name))continue;
  const marker=name.match(/^__TYPEBOX_NATIVE_(ARG|SETUP)_(f\d+|initializer)_(\d+)__$/);
  if(marker){const frame=frames.get(marker[2]);const limit=marker[1]==='ARG'?frame?.count:frame?.descriptorCount;if(marker[2]!==unit.owner||!frame||Number(marker[3])>limit)throw Error('Setup region references a foreign/out-of-range owner frame');continue}
  if(!abiNames.has(name))throw Error(`Unclosed native setup local ${name} in ${unit.kind}_${unit.id}`);
  if((name==='args'||name==='roots')&&unit.kind!=='callback')throw Error(`Native setup cannot capture callback ${name} through ${unit.kind}`);
  if(name==='args'&&!unit.flags.args)throw Error('Setup adds an arguments binding absent from original callback');
  if(name==='receiver'&&!unit.flags.receiver)throw Error('Setup adds a lexical receiver absent from original native body');
  if(name==='env'&&!unit.flags.env)throw Error('Setup adds an environment binding absent from original native body');
  needs[name]=true;
 }
 if(needs.engine)needs.s=true;
 return{declared:[...declared],referenced:[...referenced],needs};
}
function tree(unit){
 const regions=unit.regions.map(region=>({...region,children:[]})).sort((left,right)=>left.start-right.start||right.end-left.end);
 const roots=[],stack=[];let previousRootEnd=-1;
 for(const region of regions){
  if(region.start<0||region.start>region.calleeEnd||region.calleeEnd>region.end||region.callLine!==region.end||region.callLine>=unit.lines.length)throw Error('Invalid recorded native call region');
  while(stack.length&&!(region.start>=stack.at(-1).start&&region.callLine<stack.at(-1).end))stack.pop();
  if(stack.length)stack.at(-1).children.push(region);else{if(region.start<previousRootEnd)throw Error('Crossing native preparation regions');roots.push(region);previousRootEnd=region.callLine+1}
  stack.push(region);
 }
 return roots;
}
function marker(owner,offset){return`__TYPEBOX_NATIVE_SETUP_${owner}_${offset}__`}
export function admitPreparedCallStep(unit,region,frame){
 const integer=value=>Number.isSafeInteger(value)&&value>=0;
 if(!frame||frame.key!==unit.owner||!/^f(?:0|[1-9]\d*)$/.test(unit.owner)||!integer(frame.base)||!integer(frame.count)||!integer(frame.descriptorCount)||!integer(frame.base+frame.count+frame.descriptorCount))throw Error('Prepared call owner/frame identity invalid');
 if(!integer(region.resultIndex)||region.resultIndex>=frame.base||region.resultSlot!==`native_values[${region.resultIndex}]`)throw Error('Prepared call result must be its original operand slot');
 if(!integer(region.descriptor)||region.descriptor%2!==0||region.descriptor+1>=frame.descriptorCount||!frame.descriptors.some(item=>item.helper===`call_setup_${region.helper}`&&item.offset===region.descriptor&&item.count===2))throw Error('Prepared call descriptor pair is outside its existing owner allocation');
 if(region.construct!==true&&region.construct!==false)throw Error('Prepared call operation must be recorded invoke/construct');
 const range=region.argumentRange;
 if(!range||range.owner!==unit.owner||!integer(range.start)||!integer(range.count)||!integer(range.start+range.count)||(range.empty!==true&&range.empty!==false))throw Error('Prepared call argument owner/range invalid');
 let firstArg,endArg;
 if(range.empty){
  if(range.start!==0||range.count!==0||region.arguments!=='&.{}')throw Error('Prepared empty call must be original empty arguments');
  firstArg='0';endArg='0';
 }else{
  if(range.count===0||range.start+range.count>frame.count||!frame.ranges.some(item=>item.start===range.start&&item.count===range.count))throw Error('Prepared call arguments must match one exact original slice');
  const first=`__TYPEBOX_NATIVE_ARG_${unit.owner}_${range.start}__`,end=`__TYPEBOX_NATIVE_ARG_${unit.owner}_${range.start+range.count}__`;
  if(region.arguments!==`native_values[${first}..${end}]`)throw Error('Prepared call emitted argument slice differs from recorded owner/range');
  firstArg=first;endArg=end;
 }
 const original=`${region.resultSlot} = try rt.${region.construct?'construct':'invoke'}(s, ${region.callable}, ${region.construct?'':region.callReceiver+', '}${region.arguments});`;
 if(unit.lines[region.callLine]!==original)throw Error('Prepared call boundary differs from original recorded call');
 return{nativeHelper:region.construct?'constructPrepared':'invokePrepared',resultIndex:region.resultIndex,firstArg,endArg,empty:range.empty,argumentOwner:range.owner,argumentOffset:range.start,argumentCount:range.count,absoluteArgumentStart:range.empty?0:frame.base+range.start,absoluteArgumentEnd:range.empty?0:frame.base+range.start+range.count,descriptorOffset:region.descriptor,absoluteDescriptorStart:frame.base+frame.count+region.descriptor};
}
const preparedCallNative=`noinline fn invokePrepared(s: *rt.Scope, values: []c.JSValue, descriptor: usize, first_arg: usize, end_arg: usize, result: usize) anyerror!void {
values[result] = try rt.invoke(s, values[descriptor], values[descriptor + 1], values[first_arg..end_arg]);
}
noinline fn constructPrepared(s: *rt.Scope, values: []c.JSValue, descriptor: usize, first_arg: usize, end_arg: usize, result: usize) anyerror!void {
values[result] = try rt.construct(s, values[descriptor], values[first_arg..end_arg]);
}
`;
export function outlineCallPreparations(units,frames,generatedGlobals,{preparedCallSteps=false}={}){
 const helpers=[],globals=new Set(['rt','c',...generatedGlobals]);
 if(preparedCallSteps){globals.add('invokePrepared');globals.add('constructPrepared')}
 const eligible=units.filter(unit=>unit.scoped&&unit.regions.length);
 for(const frame of frames.values()){frame.descriptorCount=0;frame.descriptors=[]}
 function reserve(unit,regions){
  const frame=frames.get(unit.owner);if(!frame)throw Error('Setup owner frame missing');
  for(const region of regions){
   region.helper=helpers.length;region.descriptor=frame.descriptorCount;frame.descriptorCount+=2;
   helpers.push({unit,region});globals.add(`call_setup_${region.helper}`);
   frame.descriptors.push({helper:`call_setup_${region.helper}`,offset:region.descriptor,count:2});
   reserve(unit,region.children);
  }
 }
 for(const unit of eligible){unit.regionTree=tree(unit);reserve(unit,unit.regionTree)}
 let stepSerial=0;
 if(preparedCallSteps)for(const helper of helpers){helper.region.step={...admitPreparedCallStep(helper.unit,helper.region,frames.get(helper.unit.owner)),id:stepSerial++}}
 function descriptor(region,unit,part){return`native_values[${marker(unit.owner,region.descriptor+part)}]`}
 function realCall(region,unit){if(preparedCallSteps){const step=region.step;return`try ${step.nativeHelper}(s, native_values, ${marker(unit.owner,region.descriptor)}, ${step.firstArg}, ${step.endArg}, ${step.resultIndex});`}return`${region.resultSlot} = try rt.${region.construct?'construct':'invoke'}(s, ${descriptor(region,unit,0)}, ${region.construct?'':descriptor(region,unit,1)+', '}${region.arguments});`}
 function helperCall(helper){
  const n=helper.analysis.needs;
  const args=['s',n.env?'env':'c.pi_js_undefined()',n.receiver?'receiver':'c.pi_js_undefined()','native_values'];
  if(n.args)args.push('args');if(n.roots)args.push('roots');
  return`try call_setup_${helper.region.helper}(${args.join(', ')});`;
 }
 function render(unit,start,end,children,boundary=null){
  const lines=[];let cursor=start;
  const store=()=>lines.push(`${descriptor(boundary,unit,0)} = ${boundary.callable};`,`${descriptor(boundary,unit,1)} = ${boundary.callReceiver};`);
  function original(to){if(boundary&&cursor<=boundary.calleeEnd&&boundary.calleeEnd<=to){lines.push(...unit.lines.slice(cursor,boundary.calleeEnd));store();cursor=boundary.calleeEnd;boundary={...boundary,calleeEnd:-1}}lines.push(...unit.lines.slice(cursor,to));cursor=to}
  for(const child of children){
   if(child.start<cursor||child.callLine>=end)throw Error('Nested setup range crosses its original boundary');
   original(child.start);
   const helper=helpers[child.helper];build(helper);
   lines.push(helperCall(helper),realCall(child,unit));cursor=child.callLine+1;
  }
  original(end);
  if(boundary&&boundary.calleeEnd===end)store();
  return lines.join('\n');
 }
 function build(helper){
  if(helper.body!==undefined)return;
  const{unit,region}=helper;
  helper.body=render(unit,region.start,region.end,region.children,region);
  helper.analysis=closure(helper.body,unit,globals,frames);
  const scanned=tokens(helper.body),cleanup=new Set(['deinit','free','freeValue','destroy']);
  if(scanned.some((token,index)=>token.kind==='name'&&((token.text==='defer'||token.text==='errdefer')||((cleanup.has(token.text)||token.text.startsWith('JS_Free'))&&scanned[index+1]?.text==='('))))throw Error('Setup helper cannot acquire Scope/JSValue cleanup ownership');
 }
 for(const unit of eligible)unit.emittedBody=render(unit,0,unit.lines.length,unit.regionTree);
 for(const helper of helpers)build(helper);
 const native=(preparedCallSteps?preparedCallNative:'')+helpers.map(helper=>{
  const n=helper.analysis.needs;
  const params=[`${n.s?'s':'_'}: *rt.Scope`,`${n.env?'env':'_'}: c.JSValue`,`${n.receiver?'receiver':'_'}: c.JSValue`,'native_values: []c.JSValue'];
  if(n.args)params.push('args: []const c.JSValue');if(n.roots)params.push('roots: []const c.JSValue');
  return`noinline fn call_setup_${helper.region.helper}(${params.join(', ')}) anyerror!void {\n${n.engine?'const engine = s.engine;\n':''}${helper.body}\n}\n`;
 }).join('');
 const provenance=helpers.map(helper=>({nativeHelper:`call_setup_${helper.region.helper}`,owner:helper.unit.owner,bodyKind:helper.unit.kind,bodyId:helper.unit.id,source:helper.unit.source,start:helper.region.sourceStart,end:helper.region.sourceEnd,sourceExpressionSha256:helper.region.sourceHash,originalLines:{start:helper.region.start,calleeEnd:helper.region.calleeEnd,end:helper.region.end,call:helper.region.callLine},descriptorOffset:helper.region.descriptor,noinline:true,declaredLocals:helper.analysis.declared,referencedLocals:helper.analysis.referenced,abiNeeds:helper.analysis.needs,nestedHelpers:helper.region.children.map(child=>`call_setup_${child.helper}`)}));
 const steps=preparedCallSteps?helpers.map(helper=>({id:helper.region.step.id,nativeHelper:helper.region.step.nativeHelper,preparationHelper:`call_setup_${helper.region.helper}`,owner:helper.unit.owner,bodyKind:helper.unit.kind,bodyId:helper.unit.id,source:helper.unit.source,start:helper.region.sourceStart,end:helper.region.sourceEnd,sourceExpressionSha256:helper.region.sourceHash,originalCallLine:helper.region.callLine,resultIndex:helper.region.step.resultIndex,descriptorOffset:helper.region.step.descriptorOffset,absoluteDescriptorStart:helper.region.step.absoluteDescriptorStart,argumentOwner:helper.region.step.argumentOwner,argumentOffset:helper.region.step.argumentOffset,argumentCount:helper.region.step.argumentCount,absoluteArgumentStart:helper.region.step.absoluteArgumentStart,absoluteArgumentEnd:helper.region.step.absoluteArgumentEnd,emptyArguments:helper.region.step.empty,construct:helper.region.construct,noinline:true,resultOwnership:'Borrowed existing Scope-owned result; store only after success; no new own/dup/free/cleanup'})):[];
 return{native,provenance,steps};
}

// The continuation emitter reuses the reviewed lexical-closure scanner. Each
// Step is independently closed; no native temporary can survive a yield.
export function checkContinuationStep(body, owner, frames, generatedGlobals) {
 const analysis=closure(body,{kind:'callback',id:owner,owner,flags:{args:true,receiver:true,env:true}},new Set(['rt','c','a',...generatedGlobals]),frames);
 if(analysis.declared.length)throw Error('Continuation Step cannot capture or declare native temporaries');
 for(const token of tokens(body))if(token.kind==='name'&&(token.text==='defer'||token.text==='errdefer'||token.text==='free'||token.text==='freeValue'||token.text==='deinit'||token.text==='destroy'||token.text.startsWith('JS_Free')))throw Error('Continuation Step cannot own native cleanup');
 return analysis.needs;
}

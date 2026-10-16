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
export function outlineCallPreparations(units,frames,generatedGlobals){
 const helpers=[],globals=new Set(['rt','c',...generatedGlobals]);
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
 function descriptor(region,unit,part){return`native_values[${marker(unit.owner,region.descriptor+part)}]`}
 function realCall(region,unit){return`${region.resultSlot} = try rt.${region.construct?'construct':'invoke'}(s, ${descriptor(region,unit,0)}, ${region.construct?'':descriptor(region,unit,1)+', '}${region.arguments});`}
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
 const native=helpers.map(helper=>{
  const n=helper.analysis.needs;
  const params=[`${n.s?'s':'_'}: *rt.Scope`,`${n.env?'env':'_'}: c.JSValue`,`${n.receiver?'receiver':'_'}: c.JSValue`,'native_values: []c.JSValue'];
  if(n.args)params.push('args: []const c.JSValue');if(n.roots)params.push('roots: []const c.JSValue');
  return`noinline fn call_setup_${helper.region.helper}(${params.join(', ')}) anyerror!void {\n${n.engine?'const engine = s.engine;\n':''}${helper.body}\n}\n`;
 }).join('');
 const provenance=helpers.map(helper=>({nativeHelper:`call_setup_${helper.region.helper}`,owner:helper.unit.owner,bodyKind:helper.unit.kind,bodyId:helper.unit.id,source:helper.unit.source,start:helper.region.sourceStart,end:helper.region.sourceEnd,sourceExpressionSha256:helper.region.sourceHash,originalLines:{start:helper.region.start,calleeEnd:helper.region.calleeEnd,end:helper.region.end,call:helper.region.callLine},descriptorOffset:helper.region.descriptor,noinline:true,declaredLocals:helper.analysis.declared,referencedLocals:helper.analysis.referenced,abiNeeds:helper.analysis.needs,nestedHelpers:helper.region.children.map(child=>`call_setup_${child.helper}`)}));
 return{native,provenance};
}

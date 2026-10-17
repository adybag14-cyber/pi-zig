// Static native authoring. Acorn parses authority bytes; TypeBox is never loaded.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {outlineCallPreparations,usesNativeName} from './outline-call-setup.mjs';
import {emitContinuations,selectedContinuation} from './emit-continuations.mjs';
import {checkCallSetupAuthoring} from './outline-call-setup.test.mjs';
import {checkCallStepAuthoring} from './outline-call-steps.test.mjs';
// The existing owner sends this only after retained-handle/live-argv verification.
if(process.argv[3]==='--owned-start'&&fs.readFileSync(0,'utf8')!=='TYPEBOX_STATIC_AUTHORING_OWNED_START\n')throw Error('Static authoring owned-start token required');
if(process.argv[3]!=='--owned-start'||!process.argv[4])throw Error('Owned start and resolved workspace descriptor required');
const workspace=JSON.parse(fs.readFileSync(process.argv[4],'utf8'));
const samePath=(left,right)=>path.resolve(left).toLowerCase()===path.resolve(right).toLowerCase();
if(workspace.schema!==1||!['static_authoring','static_package_authoring'].includes(workspace.mode)||!samePath(workspace.candidate_root,fileURLToPath(new URL('../../',import.meta.url)))||!samePath(workspace.output_directory,process.argv[2]))throw Error('Static authoring workspace descriptor mismatch');
if(workspace.mode==='static_package_authoring'&&(!workspace.source_package_root||workspace.input_authority!=='source_package_only'||workspace.runtime_restoration_claim!==false))throw Error('Explicit source-only package authority required');
const setupAuthoringControls=checkCallSetupAuthoring();
const callStepAuthoringControls=checkCallStepAuthoring();
if(crypto.createHash('sha256').update(fs.readFileSync(workspace.acorn_entry)).digest('hex').toUpperCase()!==workspace.acorn_entry_sha256)throw Error('Sealed Acorn entry drift');
const {parse}=await import(pathToFileURL(workspace.acorn_entry));
const root=workspace.mode==='static_package_authoring'?path.join(workspace.source_package_root,'build'):path.join(workspace.runtime,'node_modules/typebox/build');
const packageBytes=fs.readFileSync(path.join(root,'../package.json'));
// Prospective relocated runs only write four explicitly granted fresh staged files.
const outputDirectory=path.resolve(process.argv[2]);
const outputNames=new Set(['reachable-closure.json','lowering-map.json','initialization-order.json','native_typebox_operators_production.zig']);
function writeOutput(relative,bytes){const name=path.basename(relative);if(!outputNames.has(name))throw Error('Unapproved staged output');fs.writeFileSync(path.join(outputDirectory,name),bytes,{flag:'wx'})}
if(JSON.parse(packageBytes).version!=='1.3.27'||crypto.createHash('sha256').update(packageBytes).digest('hex')!=='c59ddfd977ce941f1e8ee8b0a0b14396c332fa27cc5fa6fa165227ffd5a3992f')throw Error('Pinned TypeBox package drift');
const inputBytes=fs.readFileSync(workspace.input_path);
if(crypto.createHash('sha256').update(inputBytes).digest('hex').toUpperCase()!==workspace.input_sha256)throw Error('Sealed original input drift');
parse(inputBytes.toString('utf8'),{ecmaVersion:'latest',sourceType:'script'});
const external=new Map([
 ['system/memory/index.mjs','memory'],['system/settings/index.mjs','settings'],
 ['type/engine/evaluate/evaluate.mjs','evaluation'],
]);
const modules=new Map(),bindings=new Map(),chosen=new Map(),namespaces=new Map();
function relative(from,to){return path.posix.normalize(path.posix.join(path.posix.dirname(from),to))}
function moduleOf(file){
 if(modules.has(file))return modules.get(file);
 const source=fs.readFileSync(path.join(root,file),'utf8');if(source.includes('__TYPEBOX_NATIVE_ARG_')||source.includes('__TYPEBOX_NATIVE_SETUP_'))throw Error('Reserved static frame marker in authority');const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});
 const m={file,source,ast,id:modules.size,local:new Map(),exports:new Map(),stars:[]};modules.set(file,m);
 const add=(name,node,init)=>{const b={id:`m${m.id}_${name}`,name,node,init,module:m};m.local.set(name,b);bindings.set(b.id,b)};
 for(const stmt0 of ast.body){const stmt=stmt0.type==='ExportNamedDeclaration'&&stmt0.declaration?stmt0.declaration:stmt0;
  if(stmt.type==='ImportDeclaration')for(const s of stmt.specifiers)m.local.set(s.local.name,{import:relative(file,stmt.source.value),export:s.type==='ImportNamespaceSpecifier'?'*':s.type==='ImportDefaultSpecifier'?'default':s.imported.name});
  else if(stmt.type==='FunctionDeclaration'||stmt.type==='ClassDeclaration')add(stmt.id.name,stmt);
  else if(stmt.type==='VariableDeclaration')for(const d of stmt.declarations){if(d.id.type!=='Identifier')throw Error('Module binding pattern');add(d.id.name,d.id,d.init)}
  if(stmt0.type==='ExportNamedDeclaration'){
   if(stmt0.declaration){const d=stmt0.declaration;if(d.type==='VariableDeclaration')for(const b of d.declarations)m.exports.set(b.id.name,{local:b.id.name});else m.exports.set(d.id.name,{local:d.id.name})}
   for(const e of stmt0.specifiers)m.exports.set(e.exported.name,{...(stmt0.source?{from:relative(file,stmt0.source.value),name:e.local.name}:{local:e.local.name})});
  }else if(stmt0.type==='ExportAllDeclaration'){if(stmt0.exported)m.exports.set(stmt0.exported.name,{namespace:relative(file,stmt0.source.value)});else m.stars.push(relative(file,stmt0.source.value))}
  else if(stmt0.type==='ExportDefaultDeclaration')m.exports.set('default',stmt0.declaration.type==='Identifier'?{local:stmt0.declaration.name}:{node:stmt0.declaration});
 }
 return m;
}
function exported(file,name,seen=new Set()){
 if(external.has(file))return {external:external.get(file),name,id:`external_${external.get(file)}_${name}`};
 const key=file+'::'+name;if(seen.has(key))return null;seen.add(key);
 const m=moduleOf(file),e=m.exports.get(name);
 if(e){if(e.local)return local(m,e.local);if(e.from)return exported(e.from,e.name,seen);if(e.namespace)return {namespace:e.namespace,id:'ns_'+e.namespace};throw Error('Anonymous default export '+file)}
 for(const other of m.stars){const found=exported(other,name,new Set(seen));if(found)return found}return null;
}
function local(m,name){const b=m.local.get(name);if(!b)return null;if(b.import){if(b.export==='*')return {namespace:b.import,id:'ns_'+b.import};const result=exported(b.import,b.export);if(!result)throw Error(`Missing ${b.import}:${b.export}`);return result}return b}
function walk(node,callback,parent=null,key=''){if(!node||typeof node!=='object')return;if(node.type)callback(node,parent,key);for(const [k,value] of Object.entries(node)){if(Array.isArray(value))for(const child of value)walk(child,callback,node,k);else if(value&&typeof value==='object')walk(value,callback,node,k)}}
function choose(binding){
 if(!binding)return;if(binding.external){chosen.set(binding.id,binding);return}if(binding.namespace){throw Error('Unrestricted namespace value '+binding.namespace)}
 if(chosen.has(binding.id))return;chosen.set(binding.id,binding);
 walk(binding.init??binding.node,(n,parent,key)=>{
  if(n.type==='MemberExpression'&&n.object.type==='Identifier'){
   const target=local(binding.module,n.object.name);if(target?.namespace){const name=n.computed&&n.property.type==='Literal'?n.property.value:!n.computed?n.property.name:null;if(name===null)throw Error('Dynamic imported namespace');const member=exported(target.namespace,name);if(!member)throw Error('Missing namespace '+target.namespace+':'+name);namespaces.set(target.namespace+'::'+name,member);choose(member)}
  }
  if(n.type==='Identifier'){
   if(parent?.type==='MemberExpression'&&key==='property'&&!parent.computed)return;
   if(parent?.type==='Property'&&key==='key'&&!parent.computed)return;
   const target=local(binding.module,n.name);if(target&&!target.namespace)choose(target);
  }
 });
}
const publicRoots=new Map();
function publicRoot(name,file,sourceName=name){const binding=exported(file,sourceName);if(!binding)throw Error(`Missing root ${name}`);publicRoots.set(name,binding);choose(binding)}
publicRoot('Instantiate','type/engine/instantiate.mjs');
publicRoot('Priority','type/engine/priority/priority.mjs');
publicRoot('Extends','type/extends/extends.mjs');
publicRoot('Evaluate','type/action/evaluate.mjs');publicRoot('With','type/action/with.mjs');
publicRoot('TemplateLiteralDecode','type/engine/template_literal/decode.mjs');
for(const [file,names] of Object.entries({any:['Any','IsAny'],array:['Array','IsArray','ArrayOptions'],bigint:['BigInt','IsBigInt'],boolean:['Boolean','IsBoolean'],call:['Call','IsCall'],constructor:['Constructor','IsConstructor','ConstructorOptions'],cyclic:['Cyclic','IsCyclic'],deferred:['Deferred','IsDeferred'],dependent:['Dependent','IsDependent','DependentOptions'],function:['Function','IsFunction','FunctionOptions'],generic:['Generic','IsGeneric'],infer:['Infer','IsInfer'],integer:['Integer','IsInteger'],intersect:['Intersect','IsIntersect','IntersectOptions'],literal:['Literal','IsLiteral'],never:['Never','IsNever'],null:['Null','IsNull'],number:['Number','IsNumber'],object:['Object','IsObject','ObjectOptions'],record:['Record','RecordFromPattern','RecordKey','RecordValue','RecordPattern','RecordOptions','IsRecord'],ref:['Ref','IsRef'],rest:['Rest','IsRest'],string:['String','IsString'],symbol:['Symbol','IsSymbol'],template_literal:['TemplateLiteral','IsTemplateLiteral'],tuple:['Tuple','IsTuple','TupleOptions'],undefined:['Undefined','IsUndefined'],union:['Union','IsUnion','UnionOptions'],unknown:['Unknown','IsUnknown'],unsafe:['Unsafe','IsUnsafe'],void:['Void','IsVoid']}))for(const name of names)publicRoot(name,`type/types/${file}.mjs`);
for(const name of ['IsOptional','IsReadonly','IsImmutable'])publicRoot(name,`type/types/_${name.slice(2).toLowerCase()}.mjs`);
for(const name of ['Optional','Readonly','Immutable'])publicRoot(name,`type/types/_${name.toLowerCase()}.mjs`);
for(const name of ['Parameter','IsParameter'])publicRoot(name,'type/types/parameter.mjs');
for(const name of ['Identifier','IsIdentifier'])publicRoot(name,'type/types/identifier.mjs');
for(const name of ['IsKind','IsSchema'])publicRoot(name,'type/types/schema.mjs');
publicRoot('IsEnum','type/types/enum.mjs');
for(const name of ['IsLiteralBigInt','IsLiteralBoolean','IsLiteralNumber','IsLiteralString'])publicRoot(name,'type/types/literal.mjs');
for(const file of fs.readdirSync(path.join(root,'type/action')).filter(f=>f.endsWith('.mjs')&&f!=='index.mjs')){
 const relative=`type/action/${file}`,module=moduleOf(relative);
 for(const name of module.exports.keys())if(name!=='Partial')publicRoot(name,relative);
}
const kinds={},operators={},examples={};
for(const b of chosen.values())if(!b.external)walk(b.init??b.node,n=>{kinds[n.type]=(kinds[n.type]??0)+1;examples[n.type]??={file:b.module.file,text:b.module.source.slice(n.start,n.end).slice(0,160)};if(n.operator)operators[n.operator]=(operators[n.operator]??0)+1});
const report={version:'1.3.27',packageSha256:crypto.createHash('sha256').update(packageBytes).digest('hex'),modules:[...new Set([...chosen.values()].filter(b=>!b.external).map(b=>b.module.file))].map(file=>{const m=moduleOf(file);return{file,sha256:crypto.createHash('sha256').update(m.source).digest('hex')}}),declarations:chosen.size,publicRoots:[...publicRoots.keys()],syntax:kinds,operators,examples,externalBindings:[...chosen.values()].filter(b=>b.external)};
writeOutput('./reachable-closure.json',JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({modules:report.modules.length,declarations:report.declarations,syntax:kinds,operators},null,2));

// Lower into ordinary compiled Zig callbacks. The output contains native
// operations and literals, never an AST/source blob for runtime interpretation.
const functions=[],functionIds=new WeakMap(),branchHelpers=[],argumentFrames=new Map();let serial=0;
const setupModules=new Set(['type/engine/instantiate.mjs','type/engine/call/instantiate.mjs']);
function nativeUnit(kind,id,ctx,body){return{kind,id,owner:ctx.argumentFrame.key,source:ctx.module.file,scoped:ctx.scopedSetup,lines:ctx.lines,records:ctx.records,regions:ctx.callRegions,flags:{receiver:/\breceiver\b/.test(body),args:/\bargs\b/.test(body),env:/\benv\b/.test(body)}}}
function optionalCallee(node){let optional=false;walk(node,part=>{if(part.type==='ChainExpression'||part.optional)optional=true});return optional}
const q=value=>JSON.stringify(value).replace(/\\u([0-9a-fA-F]{4})/g,'\\u{$1}').replace(/\\b/g,'\\x08').replace(/\\f/g,'\\x0c');
const fresh=prefix=>`${prefix}_${serial++}`;
const record=(ctx,operation)=>(ctx.records??=[]).push(operation);
const line=(ctx,text,operation=null)=>{ctx.lines.push(text);record(ctx,operation??{kind:'emit',text})};
function value(ctx,expression,operation=null){const name=`native_values[${ctx.slots.count++}]`;line(ctx,`${name} = ${expression};`,operation);return name}
function argumentFrame(key){const frame={key,count:0,ranges:[],base:0};argumentFrames.set(key,frame);return frame}
function argumentMarker(frame,index){return `__TYPEBOX_NATIVE_ARG_${frame.key}_${index}__`}
function argumentsSlice(ctx,args,region=null){
 if(args.length===0){if(region)region.argumentRange={owner:ctx.argumentFrame.key,start:0,count:0,empty:true};return '&.{}'}
 const frame=ctx.argumentFrame,start=frame.count;frame.count+=args.length;
 frame.ranges.push({start,count:args.length});
 if(region)region.argumentRange={owner:frame.key,start,count:args.length,empty:false};
 args.forEach((arg,index)=>line(ctx,`native_values[${argumentMarker(frame,start+index)}] = ${arg};`));
 return `native_values[${argumentMarker(frame,start)}..${argumentMarker(frame,start+args.length)}]`;
}
function discard(ctx,result){if(/^[A-Za-z0-9_]+$/.test(result)&&(ctx.lines.join('\n').match(new RegExp('\\b'+result+'\\b','g'))??[]).length===1)line(ctx,`_ = ${result};`)}
function names(pattern,out=new Set()){if(!pattern)return out;if(pattern.type==='Identifier')out.add(pattern.name);else if(pattern.type==='ArrayPattern')for(const e of pattern.elements)names(e,out);else if(pattern.type==='AssignmentPattern')names(pattern.left,out);else if(pattern.type==='RestElement')names(pattern.argument,out);else throw Error('Pattern '+pattern.type);return out}
function localsOf(node){const result=new Set();for(const p of node.params??[])names(p,result);function visit(n){if(!n||typeof n!=='object')return;if(n!==node&&(n.type==='FunctionDeclaration'||n.type==='FunctionExpression'||n.type==='ArrowFunctionExpression')){if(n.type==='FunctionDeclaration')result.add(n.id.name);return}if(n.type==='VariableDeclarator')names(n.id,result);for(const v of Object.values(n))if(Array.isArray(v))v.forEach(visit);else if(v&&typeof v==='object')visit(v)}visit(node.body);return result}
function nameOf(ctx,name){if(ctx.locals.has(name))return name;const binding=local(ctx.module,name);if(binding?.namespace)throw Error('Bare namespace '+name);return binding?.id??name}
function bindPattern(ctx,pattern,input){
 if(!pattern)return;
 if(pattern.type==='Identifier'){line(ctx,`try rt.bind(s, env, ${q(nameOf(ctx,pattern.name))}, ${input});`);return}
 if(pattern.type==='AssignmentPattern'){
  const result=fresh('default');line(ctx,`var ${result} = ${input};`);line(ctx,`if (rt.defaulted(${result})) {`);const fallback=expr(ctx,pattern.right,pattern.left.type==='Identifier'?pattern.left.name:'');line(ctx,`${result} = ${fallback};`);line(ctx,'}');bindPattern(ctx,pattern.left,result);return;
 }
 if(pattern.type==='RestElement'){bindPattern(ctx,pattern.argument,input);return}
 if(pattern.type==='ArrayPattern'){
  const iterator=fresh('iterator');line(ctx,'{');line(ctx,`var ${iterator} = try rt.iterator(s, ${input});`);line(ctx,`defer ${iterator}.deinit();`);line(ctx,`errdefer ${iterator}.closePreserving();`);
  for(const element of pattern.elements){const item=value(ctx,element?.type==='RestElement'?`try rt.iteratorRest(s, &${iterator})`:`try rt.iteratorValue(s, &${iterator})`);if(element)bindPattern(ctx,element,item);else line(ctx,`_ = ${item};`)}line(ctx,`try ${iterator}.close();`);line(ctx,'}');return;
 }
 throw Error('Unsupported binding '+pattern.type);
}
function compileFunction(node,module,inferred='',ancestors=new Set()){
 if(functionIds.has(node))return functionIds.get(node);
 const id=functions.length;functionIds.set(node,id);functions.push(null);
 const ctx={module,locals:new Set([...ancestors,...localsOf(node)]),lines:[],records:[],receiver:'receiver',slots:{count:0},argumentFrame:argumentFrame(`f${id}`),scopedSetup:setupModules.has(module.file),continuationSelected:selectedContinuation(module.file,node.id?.name??inferred),callRegions:[]};
 for(let i=0;i<node.params.length;i++){const p=node.params[i];const input=value(ctx,p.type==='RestElement'?`try rt.rest(s, args, ${i})`:`rt.argument(args, ${i})`);bindPattern(ctx,p,input)}
 if(node.body.type==='BlockStatement'){statement(ctx,node.body);if(!returns(node.body))line(ctx,'return c.pi_js_undefined();',{kind:'returned',value:'c.pi_js_undefined()'})}
 else {const output=expr(ctx,node.body);line(ctx,`return c.JS_DupValue(engine.context, ${output});`,{kind:'returned',value:output})}
 const sourceName=node.id?.name??inferred;
 const length=node.params.findIndex(p=>p.type==='AssignmentPattern'||p.type==='RestElement');
 const body=ctx.lines.join('\n'),usesReceiver=/\breceiver\b/.test(body),usesArgs=/\bargs\b/.test(body);
 const arrow=node.type==='ArrowFunctionExpression';
 ctx.argumentFrame.base=ctx.slots.count;
 functions[id]={id,node,module,name:sourceName,length:length<0?node.params.length:length,arrow,body,usesReceiver,usesArgs,usesEnv:/\benv\b/.test(body),unit:nativeUnit('callback',id,ctx,body),slots:ctx.slots.count+ctx.argumentFrame.count,originalSlots:ctx.slots.count,argumentSlots:ctx.argumentFrame.count,argumentSlices:ctx.argumentFrame.ranges.map(range=>({start:ctx.slots.count+range.start,count:range.count}))};return id;
}
function branchFunction(ctx,node){
 const id=branchHelpers.length,helper={...ctx,lines:[],records:[],callRegions:[],receiver:'receiver'};branchHelpers.push(null);
 const conditional=node.type==='ConditionalExpression';
 const left=expr(helper,conditional?node.test:node.left);
 const condition=conditional?`s.truthy(${left})`:node.operator==='&&'?`s.truthy(${left})`:node.operator==='||'?`!s.truthy(${left})`:`rt.nullish(${left})`;
 function complete(next){
  if(next.type==='ConditionalExpression'||next.type==='LogicalExpression'){
   const child=branchFunction(helper,next);line(helper,`return .{ .jump = ${child} };`,{kind:'branch_jump',id:child});
  }else{const output=expr(helper,next);line(helper,`return .{ .value = ${output} };`,{kind:'branch_value',value:output})}
 }
 line(helper,`if (${condition}) {`,{kind:'if',test:condition});complete(conditional?node.consequent:node.right);line(helper,'} else {',{kind:'else'});
 if(conditional)complete(node.alternate);else line(helper,`return .{ .value = ${left} };`,{kind:'branch_value',value:left});
 line(helper,'}',{kind:'endif'});const body=helper.lines.join('\n');branchHelpers[id]={body,unit:nativeUnit('branch',id,helper,body),source:ctx.module.file,start:node.start,end:node.end};return id;
}
function functionValue(ctx,node,inferred=''){
 const id=compileFunction(node,ctx.module,inferred,ctx.locals),f=functions[id];
 return value(ctx,`try rt.${selectedContinuation(f.module.file,f.name)?'plannedFunction':'function'}(s, ${q(f.name)}, ${f.length}, f_${id}, env, ${ctx.receiver}, ${f.arrow}${selectedContinuation(f.module.file,f.name)?`, &typebox_plan_${id}`:''})`);
}
function member(ctx,node){
 const object=expr(ctx,node.object),raw=node.computed?expr(ctx,node.property):value(ctx,`try s.text(${q(node.property.name)})`);const key=value(ctx,`try rt.propertyKey(s, ${raw})`);return{object,key};
}
function assign(ctx,node,result){
 if(node.type==='Identifier'){line(ctx,`try rt.assign(s, env, ${q(nameOf(ctx,node.name))}, ${result});`);return}
 throw Error('Assignment reference must be prepared before its value');
}
function expr(ctx,node,inferred=''){
 if(!node) return 'c.pi_js_undefined()';
 switch(node.type){
  case 'Identifier':return node.name==='undefined'?'c.pi_js_undefined()':value(ctx,`try rt.get(s, env, ${q(nameOf(ctx,node.name))})`);
  case 'Literal':
   if(node.regex)return value(ctx,`try rt.regexp(s, ${q(node.regex.pattern)}, ${q(node.regex.flags)})`);
   if(node.bigint){const args=argumentsSlice(ctx,[`try s.text(${q(node.bigint)})`]);return value(ctx,`try rt.invoke(s, engine.intrinsic_bigint_constructor, c.pi_js_undefined(), ${args})`)}
   if(node.value===null)return 'c.pi_js_null()';
   if(typeof node.value==='boolean')return `c.pi_js_bool(engine.context, ${+node.value})`;
   if(typeof node.value==='number')return `c.JS_NewFloat64(engine.context, ${Object.is(node.value,-0)?'-0.0':JSON.stringify(node.value)})`;
   return value(ctx,`try s.text(${q(node.value)})`);
  case 'ThisExpression':return ctx.receiver;
  case 'ArrowFunctionExpression':case 'FunctionExpression':return functionValue(ctx,node,inferred);
  case 'MemberExpression':{
   if(node.object.type==='Identifier'&&!ctx.locals.has(node.object.name)){const target=local(ctx.module,node.object.name);if(target?.namespace){const name=node.computed?node.property.value:node.property.name;const b=namespaces.get(target.namespace+'::'+name)??exported(target.namespace,name);return value(ctx,`try rt.get(s, env, ${q(b.id)})`)}}
   const m=member(ctx,node);return value(ctx,`try rt.key(s, ${m.object}, ${m.key})`);
  }
  case 'CallExpression':case 'NewExpression':{
   if(ctx.continuationSelected&&(node.optional||optionalCallee(node.callee)||node.arguments.some(arg=>arg.type==='SpreadElement')))throw Error('Unsupported selected continuation call form');
   const region=ctx.scopedSetup&&!node.optional&&!optionalCallee(node.callee)&&!node.arguments.some(arg=>arg.type==='SpreadElement')?{start:ctx.lines.length,sourceStart:node.start,sourceEnd:node.end,sourceHash:crypto.createHash('sha256').update(ctx.module.source.slice(node.start,node.end)).digest('hex'),construct:node.type==='NewExpression'}:null;
   let callable,receiver='c.pi_js_undefined()';
   if(node.callee.type==='MemberExpression'&&!(node.callee.object.type==='Identifier'&&!ctx.locals.has(node.callee.object.name)&&local(ctx.module,node.callee.object.name)?.namespace)){const m=member(ctx,node.callee);receiver=m.object;callable=value(ctx,`try rt.key(s, ${m.object}, ${m.key})`)}else callable=expr(ctx,node.callee);
   if(region){region.calleeEnd=ctx.lines.length;region.callable=callable;region.callReceiver=receiver}
   const optional=node.optional;let output;
   if(optional){output=fresh('optional');line(ctx,`var ${output} = c.pi_js_undefined();`);line(ctx,`if (!rt.nullish(${callable})) {`)}
   let result;const continuationCall=ctx.continuationSelected?{kind:'call',owner:ctx.argumentFrame.key,callable,receiver,construct:node.type==='NewExpression'}:null;
   if(node.arguments.some(a=>a.type==='SpreadElement')){
    if(node.type==='NewExpression')throw Error('New spread');const array=value(ctx,'try s.array()');for(const a of node.arguments){const input=expr(ctx,a.type==='SpreadElement'?a.argument:a);line(ctx,`try rt.${a.type==='SpreadElement'?'spreadArray':'append'}(s, ${array}, ${input});`)}result=`try rt.invokeSpread(s, ${callable}, ${receiver}, ${array})`;
   }else{const args=argumentsSlice(ctx,node.arguments.map(a=>expr(ctx,a)),region??continuationCall);if(region)region.arguments=args;if(continuationCall){continuationCall.args=args;continuationCall.range=(region??continuationCall).argumentRange;continuationCall.result=ctx.slots.count}result=node.type==='NewExpression'?`try rt.construct(s, ${callable}, ${args})`:`try rt.invoke(s, ${callable}, ${receiver}, ${args})`}
   if(optional){line(ctx,`${output} = ${result};`);line(ctx,'}');return output}
   if(region){region.end=ctx.lines.length;region.callLine=ctx.lines.length;region.resultIndex=ctx.slots.count;region.resultSlot=value(ctx,result,continuationCall);ctx.callRegions.push(region);return region.resultSlot}
   return value(ctx,result,continuationCall);
  }
  case 'ChainExpression':return expr(ctx,node.expression);
  case 'ArrayExpression':{
   const array=value(ctx,'try s.array()');for(const element of node.elements){if(!element)throw Error('Literal array hole');const input=expr(ctx,element.type==='SpreadElement'?element.argument:element);line(ctx,`try rt.${element.type==='SpreadElement'?'spreadArray':'append'}(s, ${array}, ${input});`)}return array;
  }
  case 'ObjectExpression':{
   const object=value(ctx,'try s.object()');for(const property of node.properties){if(property.type==='SpreadElement'){const input=expr(ctx,property.argument);line(ctx,`try rt.spreadObject(s, ${object}, ${input});`)}else{
    if(property.kind!=='init'||property.method)throw Error('Object accessor/method');const rawKey=property.computed?expr(ctx,property.key):value(ctx,`try s.text(${q(property.key.name??String(property.key.value))})`);const key=value(ctx,`try rt.propertyKey(s, ${rawKey})`);const input=expr(ctx,property.value,property.key.name??'');line(ctx,`try rt.property(s, ${object}, ${key}, ${input});`)
   }}return object;
  }
  case 'ConditionalExpression':case 'LogicalExpression':{
   const id=branchFunction(ctx,node);return value(ctx,`try runBranch(s, env, ${ctx.receiver}, native_values, ${id})`,{kind:'branch_result',id,result:ctx.slots.count});
  }
  case 'BinaryExpression':{if(!['+','-','*','/','<','<=','>','>=','%','**','&','|','<<','>>','===','!==','in','instanceof'].includes(node.operator))throw Error('Unlowered binary '+node.operator);const left=expr(ctx,node.left),right=expr(ctx,node.right);return value(ctx,`try rt.binary(s, ${q(node.operator)}, ${left}, ${right})`)}
  case 'UnaryExpression':{if(node.operator==='-'&&node.argument.type==='Literal'&&typeof node.argument.value==='number')return expr(ctx,{type:'Literal',value:-node.argument.value});if(!['!','typeof'].includes(node.operator))throw Error('Unlowered unary '+node.operator);const input=expr(ctx,node.argument);return value(ctx,`try rt.unary(s, ${q(node.operator)}, ${input})`)}
  case 'TemplateLiteral':{
   let current=value(ctx,`try s.text(${q(node.quasis[0].value.cooked)})`);
   for(let i=0;i<node.expressions.length;i++){const raw=expr(ctx,node.expressions[i]),text=value(ctx,`try s.stringify(${raw})`);current=value(ctx,`try s.concat(${current}, ${text})`);const suffix=value(ctx,`try s.text(${q(node.quasis[i+1].value.cooked)})`);current=value(ctx,`try s.concat(${current}, ${suffix})`)}return current;
  }
  case 'AssignmentExpression':{
   if(node.operator!=='=')throw Error('Compound assignment');const target=node.left.type==='MemberExpression'?member(ctx,node.left):null;const output=expr(ctx,node.right,node.left.name??'');if(target)line(ctx,`try rt.set(s, ${target.object}, ${target.key}, ${output});`);else assign(ctx,node.left,output);return output;
  }
  case 'UpdateExpression':{
   if(node.argument.type!=='Identifier')throw Error('Update property');const before=expr(ctx,node.argument),after=value(ctx,`try rt.update(s, ${before}, ${node.operator==='++'})`);assign(ctx,node.argument,after);return node.prefix?after:before;
  }
  default:throw Error('Unlowered expression '+node.type+' in '+ctx.module.file);
 }
}
function returns(node){if(!node)return false;if(node.type==='ReturnStatement'||node.type==='ThrowStatement')return true;if(node.type==='BlockStatement')return node.body.some(returns);if(node.type==='IfStatement')return returns(node.consequent)&&returns(node.alternate);if(node.type==='TryStatement')return returns(node.block)||returns(node.finalizer);return false}
const tryHelpers=[];
function statement(ctx,node){
 if(!node)return;
 switch(node.type){
  case 'BlockStatement':
   for(const fn of node.body.filter(n=>n.type==='FunctionDeclaration')){const output=functionValue(ctx,fn,fn.id.name);line(ctx,`try rt.bind(s, env, ${q(fn.id.name)}, ${output});`)}
   for(const stmt of node.body)if(stmt.type!=='FunctionDeclaration')statement(ctx,stmt);return;
  case 'ReturnStatement':{const output=expr(ctx,node.argument);line(ctx,`return c.JS_DupValue(engine.context, ${output});`,{kind:'returned',value:output});return}
  case 'ThrowStatement':{const output=expr(ctx,node.argument);line(ctx,`return rt.throwValue(s, ${output});`,{kind:'thrown',value:output});return}
  case 'VariableDeclaration':for(const declaration of node.declarations)bindPattern(ctx,declaration.id,expr(ctx,declaration.init,declaration.id.name??''));return;
  case 'ExpressionStatement':{const result=expr(ctx,node.expression);discard(ctx,result);return}
  case 'IfStatement':{const test=expr(ctx,node.test);line(ctx,`if (s.truthy(${test})) {`,{kind:'if',test:`s.truthy(${test})`});statement(ctx,node.consequent);if(node.alternate){line(ctx,'} else {',{kind:'else'});statement(ctx,node.alternate)}line(ctx,'}',{kind:'endif'});return}
  case 'ForOfStatement':{
   const source=expr(ctx,node.right),iterator=fresh('loop');line(ctx,'{');line(ctx,`var ${iterator} = try rt.iterator(s, ${source});`);line(ctx,`defer ${iterator}.deinit();`);line(ctx,`errdefer ${iterator}.closePreserving();`);const item=fresh('item');line(ctx,`while (try ${iterator}.next()) |${item}| {`);line(ctx,`defer engine.freeValue(${item});`);bindPattern(ctx,node.left.declarations[0].id,item);statement(ctx,node.body);line(ctx,'}');line(ctx,'}');return;
  }
  case 'ForStatement':{
   line(ctx,'{');statement(ctx,node.init);line(ctx,'while (true) {');if(node.test){const test=expr(ctx,node.test);line(ctx,`if (!s.truthy(${test})) break;`)}statement(ctx,node.body);if(node.update){const result=expr(ctx,node.update);discard(ctx,result)}line(ctx,'}');line(ctx,'}');return;
  }
  case 'TryStatement':{
   if(node.handler||!returns(node.block)||returns(node.finalizer))throw Error('Unexpected try control shape');
   const id=tryHelpers.length,helper={...ctx,lines:[],records:[],callRegions:[]};tryHelpers.push(null);statement(helper,node.block);const body=helper.lines.join('\n');tryHelpers[id]={body,unit:nativeUnit('try',id,helper,body)};
   const result=fresh('completion');line(ctx,`const ${result} = try_block_${id}(s, env, ${ctx.receiver}, native_values);`,{kind:'try',id});line(ctx,`errdefer if (${result}) |returned| engine.freeValue(returned) else |_| {};`,{kind:'ignore'});statement(ctx,node.finalizer);record(ctx,{kind:'end_finally'});line(ctx,`return ${result};`,{kind:'ignore'});return;
  }
  default:throw Error('Unlowered statement '+node.type+' in '+ctx.module.file);
 }
}
const initialize={module:null,locals:new Set(),lines:[],records:[],receiver:'c.pi_js_undefined()',slots:{count:0},argumentFrame:argumentFrame('initializer'),scopedSetup:false,callRegions:[]};
for(const b of chosen.values())if(!b.external&&(b.init||b.node.type==='ClassDeclaration'))line(initialize,`try rt.declare(s, env, ${q(b.id)});`);
for(const b of chosen.values()){
 if(b.external){const operations=['EvaluateTemplateLiteral','EvaluateEnum','EvaluateIntersect','EvaluateType','EvaluateUnion','EvaluateDependent','EvaluateUnionFast'];const lengths=[1,1,1,1,1,3,1];
  const rhs=b.external==='evaluation'?`try rt.evaluationBinding(s, graph, ${q(b.name)}, ${operations.indexOf(b.name)}, ${lengths[operations.indexOf(b.name)]})`:`try s.get(graph, ${q(b.name)})`;line(initialize,`try rt.bind(s, env, ${q(b.id)}, ${rhs});`);
 }else if(b.node.type==='FunctionDeclaration'){
  const id=compileFunction(b.node,b.module,b.name),f=functions[id];line(initialize,`try rt.bind(s, env, ${q(b.id)}, try rt.${selectedContinuation(f.module.file,f.name)?'plannedFunction':'function'}(s, ${q(f.name)}, ${f.length}, f_${id}, env, c.pi_js_undefined(), false${selectedContinuation(f.module.file,f.name)?`, &typebox_plan_${id}`:''}));`);
 }
}
const initialized=new Set(),initializationOrder=[];
function initializeModule(file){if(initialized.has(file)||external.has(file)||!modules.has(file))return;initialized.add(file);const m=moduleOf(file);for(const stmt of m.ast.body)if(stmt.source)initializeModule(relative(file,stmt.source.value));
 // ESM evaluates selected variable initializers in their original declaration
 // order. Dependency discovery order may encounter Digit before Zero/NonZero.
 for(const b of m.local.values())if(b.module===m&&chosen.has(b.id)){
  if(b.init||b.node.type==='ClassDeclaration')initializationOrder.push({module:m.file,moduleSha256:crypto.createHash('sha256').update(m.source).digest('hex'),binding:b.id,name:b.name,start:b.node.start,kind:b.node.type==='ClassDeclaration'?'class':'lexical-variable'});
  if(b.node.type==='ClassDeclaration'){
   if(b.name!=='InvalidLiteralValue')throw Error('Unlowered class '+b.name);line(initialize,`try rt.bind(s, env, ${q(b.id)}, try s.own(try @import("native_typebox_errors.zig").literalConstructor(engine)));`);
  }else if(b.init){initialize.module=m;const output=expr(initialize,b.init,b.name);line(initialize,`try rt.bind(s, env, ${q(b.id)}, ${output});`)}
 }
}
for(const b of chosen.values())if(!b.external)initializeModule(b.module.file);
initialize.argumentFrame.base=initialize.slots.count;
const continuationSelectedIds=functions.filter(f=>selectedContinuation(f.module.file,f.name)).map(f=>f.id);
if(functions.length!==1669||branchHelpers.length!==585||tryHelpers.length!==1||JSON.stringify(continuationSelectedIds)!=='[0,1,9,30,31,32,33,296,297,298,303,450,451,625,628,637,638,642,660,661,662,663,664,666,667,668,669,670,671,672,673,674,675,686]')throw Error('Pinned original callback/branch/try or finite34 identity changed');
const frozenLowering={serial,callbacks:functions.length,branches:branchHelpers.length,tries:tryHelpers.length,identities:JSON.stringify(functions.map(f=>({id:f.id,name:f.name,length:f.length,arrow:f.arrow,usesReceiver:f.usesReceiver,usesArgs:f.usesArgs,usesEnv:f.usesEnv,originalSlots:f.originalSlots,argumentSlots:f.argumentSlots,argumentSlices:f.argumentSlices})))};
if(functions.filter(f=>f.unit.scoped).length!==24)throw Error('Measured setup scope must remain exactly24 callbacks');
const setupUnits=[...functions.map(f=>f.unit),...tryHelpers.map(h=>h.unit),...branchHelpers.map(h=>h.unit)];
const bodyIdentity=()=>JSON.stringify(setupUnits.map(unit=>({kind:unit.kind,id:unit.id,owner:unit.owner,flags:unit.flags,bodySha256:crypto.createHash('sha256').update(unit.lines.join('\n')).digest('hex')})));
const frozenBodies=bodyIdentity();
const frozenCallRegions=JSON.stringify(setupUnits.map(unit=>unit.regions));
const outlined=outlineCallPreparations(setupUnits,argumentFrames,['runBranch',...continuationSelectedIds.map(id=>`typebox_plan_${id}`),...functions.map(f=>`f_${f.id}`),...tryHelpers.map((_,id)=>`try_block_${id}`),...branchHelpers.map((_,id)=>`branch_${id}`)],{preparedCallSteps:true});
if(JSON.stringify(setupUnits.map(unit=>unit.regions))!==frozenCallRegions)throw Error('Call steps changed original recorded regions');
if(outlined.provenance.length!==165||outlined.steps.length!==165||outlined.steps.some(step=>step.construct)||outlined.steps.filter(step=>step.emptyArguments).length!==4||[...argumentFrames.values()].reduce((count,frame)=>count+frame.descriptorCount,0)!==330)throw Error('Pinned165 invoke/0 construct/4 empty/330 descriptor scope differs');
if(serial!==frozenLowering.serial||functions.length!==frozenLowering.callbacks||branchHelpers.length!==frozenLowering.branches||tryHelpers.length!==frozenLowering.tries||bodyIdentity()!==frozenBodies||JSON.stringify(functions.map(f=>({id:f.id,name:f.name,length:f.length,arrow:f.arrow,usesReceiver:f.usesReceiver,usesArgs:f.usesArgs,usesEnv:f.usesEnv,originalSlots:f.originalSlots,argumentSlots:f.argumentSlots,argumentSlices:f.argumentSlices})))!==frozenLowering.identities)throw Error('Outlining changed original lowering identity');
if(initialize.argumentFrame.descriptorCount!==0)throw Error('Setup descriptors escaped the selected callback scope');
for(const f of functions){const descriptors=argumentFrames.get(`f${f.id}`).descriptorCount;if(!f.unit.scoped&&descriptors)throw Error('Setup descriptors escaped the24 measured callbacks');f.slots+=descriptors}
const continuationOutput=emitContinuations(functions,branchHelpers,tryHelpers,argumentFrames);
const prelude='//! Generated native operations from pinned TypeBox1.3.27 authority.\n//! Static authoring only; no Source evaluation or runtime AST interpreter.\nconst rt = @import("native_typebox_operators_runtime.zig");\nconst c = rt.c;\nconst BranchResult = union(enum) { value: c.JSValue, jump: usize };\nconst BranchHelper = *const fn (*rt.Scope, c.JSValue, c.JSValue, []c.JSValue) anyerror!BranchResult;\n';
let native=prelude;
for(const f of functions){
 native+=`fn f_${f.id}(engine: *rt.Engine, ${f.usesReceiver&&!f.arrow?'receiver':'_'}: c.JSValue, ${f.usesArgs?'args':'_'}: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {\nconst s = try engine.gpa.create(rt.Scope);\ns.* = .{ .engine = engine };\ndefer { s.deinit(); engine.gpa.destroy(s); }\n${f.usesEnv?'const env':'_'} = try rt.environment(s, roots[0]);\n`;
 if(f.arrow&&f.usesReceiver)native+='const receiver = roots[1];\n';if(f.slots)native+=`const native_values = try engine.gpa.alloc(c.JSValue, ${f.slots});\ndefer engine.gpa.free(native_values);\n`;native+=(f.unit.emittedBody??f.body)+'\n}\n';
}
for(let i=0;i<tryHelpers.length;i++){const h=tryHelpers[i],body=h.unit.emittedBody??h.body,needsEngine=h.unit.emittedBody!==undefined?usesNativeName(body,'engine'):true;native+=`fn try_block_${i}(s: *rt.Scope, env: c.JSValue, ${h.unit.flags.receiver?'receiver':'_'}: c.JSValue, native_values: []c.JSValue) anyerror!c.JSValue {\n${needsEngine?'const engine = s.engine;\n':''}${body}\n}\n`}
for(let i=0;i<branchHelpers.length;i++){const h=branchHelpers[i],body=h.unit.emittedBody??h.body,needsEngine=h.unit.emittedBody!==undefined?usesNativeName(body,'engine'):/\bengine\b/.test(h.body);native+=`fn branch_${i}(s: *rt.Scope, ${h.unit.flags.env?'env':'_'}: c.JSValue, ${h.unit.flags.receiver?'receiver':'_'}: c.JSValue, ${/\bnative_values\b/.test(h.body)?'native_values':'_'}: []c.JSValue) anyerror!BranchResult {\n${needsEngine?'const engine = s.engine;\n':''}${body}\n}\n`}
native+='const branch_helpers = [_]BranchHelper { '+branchHelpers.map((_,i)=>`branch_${i}`).join(', ')+' };\n';
native+='fn runBranch(s: *rt.Scope, env: c.JSValue, receiver: c.JSValue, native_values: []c.JSValue, initial: usize) anyerror!c.JSValue {\nvar next = initial;\nwhile (true) {\nconst result = try branch_helpers[next](s, env, receiver, native_values);\nswitch (result) { .jump => |child| next = child, .value => |value| return value }\n}\n}\n';
native+=outlined.native;
native+=continuationOutput.native;
native+='pub fn create(engine: *rt.Engine, graph: c.JSValue) !c.JSValue {\nconst s = try engine.gpa.create(rt.Scope);\ns.* = .{ .engine = engine };\ndefer { s.deinit(); engine.gpa.destroy(s); }\nconst env = try rt.environment(s, c.pi_js_null());\n'+`const native_values = try engine.gpa.alloc(c.JSValue, ${initialize.slots.count+initialize.argumentFrame.count});\ndefer engine.gpa.free(native_values);\n`+initialize.lines.join('\n')+'\nconst namespace = try s.object();\n';
for(const [name,b] of publicRoots)native+=`try s.put(namespace, ${q(name)}, try rt.get(s, env, ${q(b.id)}));\n`;
native+='return c.JS_DupValue(engine.context, namespace);\n}\n';
native+='pub fn install(engine: *rt.Engine, type_builder: c.JSValue, graph: c.JSValue) !void {\nconst namespace = try create(engine, graph);\ndefer engine.freeValue(namespace);\ntry @import("native_js_values.zig").spreadInto(engine, type_builder, namespace);\n}\n';
native=native.replace(/__TYPEBOX_NATIVE_ARG_(f\d+|initializer)_(\d+)__/g,(_,key,index)=>{const frame=argumentFrames.get(key),offset=Number(index);if(!frame||offset>frame.count)throw Error('Invalid static argument offset');return String(frame.base+offset)});
native=native.replace(/__TYPEBOX_NATIVE_SETUP_(f\d+)_(\d+)__/g,(_,key,index)=>{const frame=argumentFrames.get(key),offset=Number(index);if(!frame||offset>=frame.descriptorCount)throw Error('Invalid setup descriptor offset');return String(frame.base+frame.count+offset)});
if(native.includes('__TYPEBOX_NATIVE_ARG_')||native.includes('__TYPEBOX_NATIVE_SETUP_'))throw Error('Unresolved static frame offset');
writeOutput('../../src/extensions/native_typebox_operators_production.zig',native);
writeOutput('./lowering-map.json',JSON.stringify({format:'compiled-native-source-span-map-v1',heapContinuations:{selectedCallbacks:34,sourceOnlyAuthoring:true,steps:continuationOutput.provenance,legacyCallbackIdentityOnly:true},functions:functions.map(f=>({nativeCallback:`f_${f.id}`,source:f.module.file,start:f.node.start,end:f.node.end,sourceDeclarationSha256:crypto.createHash('sha256').update(f.module.source.slice(f.node.start,f.node.end)).digest('hex'),name:f.name,length:f.length,arrow:f.arrow,originalUsesReceiver:f.usesReceiver,originalUsesArgs:f.usesArgs,originalUsesEnv:f.usesEnv,heapOperandSlots:f.slots,originalOperandSlots:f.originalSlots,appendedArgumentSlots:f.argumentSlots,callArgumentSlices:f.argumentSlices,setupDescriptorSlots:argumentFrames.get(`f${f.id}`).descriptorCount,setupDescriptors:argumentFrames.get(`f${f.id}`).descriptors.map(item=>({...item,start:f.originalSlots+f.argumentSlots+item.offset}))})),nativeRawSha256:crypto.createHash('sha256').update(native).digest('hex'),tryHelpers:tryHelpers.length,operandStorage:'GPA-backed callback frame; borrowed JSValues remain traced by original Scope/cells',callbackScopeStorage:'GPA-owned original Scope; existing tracing and callback lifetime preserved',callArgumentStorage:'Disjoint appended argument area after original operand slots; borrowed pre-evaluated values',callSetup:{selectedModules:[...setupModules],selectedCallbacks:24,originalFreshSerial:frozenLowering.serial,identityFrozen:true,helpers:outlined.provenance,actualCallSteps:{sharedHelpers:[{nativeHelper:"invokePrepared",noinline:true,recordedUses:outlined.steps.filter(step=>!step.construct).length},{nativeHelper:"constructPrepared",noinline:true,recordedUses:outlined.steps.filter(step=>step.construct).length,constructorPathExercised:false}],steps:outlined.steps,count:outlined.steps.length,emptyArguments:outlined.steps.filter(step=>step.emptyArguments).length,ownership:"Borrow original heap Scope/frame; no additional own/dup/free/cleanup"}},initializerOriginalOperandSlots:initialize.slots.count,initializerHeapOperandSlots:initialize.slots.count+initialize.argumentFrame.count,initializerArgumentSlices:initialize.argumentFrame.ranges.map(range=>({start:initialize.slots.count+range.start,count:range.count})),branches:branchHelpers.map((h,id)=>({nativeHelper:`branch_${id}`,source:h.source,start:h.start,end:h.end,iterativeJumpChained:true}))},null,2)+'\n');
for(const file of new Set(initializationOrder.map(row=>row.module))){const selected=initializationOrder.filter(row=>row.module===file);for(let index=1;index<selected.length;index++)if(selected[index-1].start>=selected[index].start)throw Error('Original declaration order regression '+file)}
writeOutput('./initialization-order.json',JSON.stringify({format:'actual-source-module-initialization-order-v1',lexicalBindings:initializationOrder.length,functionsHoisted:true,lexicalTdzPreserved:true,rows:initializationOrder},null,2)+'\n');
console.log(JSON.stringify({generatedFunctions:functions.length,tryHelpers:tryHelpers.length,setupHelpers:outlined.provenance.length,setupAuthoringControls,actualCallSteps:outlined.steps.length,callStepAuthoringControls,bytes:Buffer.byteLength(native),nativeSha256:crypto.createHash('sha256').update(native).digest('hex')},null,2));

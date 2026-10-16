// Static native authoring. Acorn parses authority bytes; TypeBox is never loaded.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {parse} from 'file:///C:/Users/adyba/AppData/Roaming/npm/node_modules/wrangler/node_modules/acorn/dist/acorn.mjs';
const root='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/typebox/build';
const packageBytes=fs.readFileSync(path.join(root,'../package.json'));
if(JSON.parse(packageBytes).version!=='1.3.27'||crypto.createHash('sha256').update(packageBytes).digest('hex')!=='c59ddfd977ce941f1e8ee8b0a0b14396c332fa27cc5fa6fa165227ffd5a3992f')throw Error('Pinned TypeBox package drift');
parse(fs.readFileSync(new URL('../../src/extensions/fixtures/typebox-operators-production.input.txt',import.meta.url),'utf8'),{ecmaVersion:'latest',sourceType:'script'});
const external=new Map([
 ['system/memory/index.mjs','memory'],['system/settings/index.mjs','settings'],
 ['type/engine/evaluate/evaluate.mjs','evaluation'],
]);
const modules=new Map(),bindings=new Map(),chosen=new Map(),namespaces=new Map();
function relative(from,to){return path.posix.normalize(path.posix.join(path.posix.dirname(from),to))}
function moduleOf(file){
 if(modules.has(file))return modules.get(file);
 const source=fs.readFileSync(path.join(root,file),'utf8'),ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});
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
fs.writeFileSync(new URL('./reachable-closure.json',import.meta.url),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({modules:report.modules.length,declarations:report.declarations,syntax:kinds,operators},null,2));

// Lower into ordinary compiled Zig callbacks. The output contains native
// operations and literals, never an AST/source blob for runtime interpretation.
const functions=[],functionIds=new WeakMap(),branchHelpers=[];let serial=0;
const q=value=>JSON.stringify(value).replace(/\\u([0-9a-fA-F]{4})/g,'\\u{$1}').replace(/\\b/g,'\\x08').replace(/\\f/g,'\\x0c');
const fresh=prefix=>`${prefix}_${serial++}`;
const line=(ctx,text)=>ctx.lines.push(text);
function value(ctx,expression){const name=`native_values[${ctx.slots.count++}]`;line(ctx,`${name} = ${expression};`);return name}
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
 const ctx={module,locals:new Set([...ancestors,...localsOf(node)]),lines:[],receiver:'receiver',slots:{count:0}};
 for(let i=0;i<node.params.length;i++){const p=node.params[i];const input=value(ctx,p.type==='RestElement'?`try rt.rest(s, args, ${i})`:`rt.argument(args, ${i})`);bindPattern(ctx,p,input)}
 if(node.body.type==='BlockStatement'){statement(ctx,node.body);if(!returns(node.body))line(ctx,'return c.pi_js_undefined();')}
 else {const output=expr(ctx,node.body);line(ctx,`return c.JS_DupValue(engine.context, ${output});`)}
 const sourceName=node.id?.name??inferred;
 const length=node.params.findIndex(p=>p.type==='AssignmentPattern'||p.type==='RestElement');
 const body=ctx.lines.join('\n'),usesReceiver=/\breceiver\b/.test(body),usesArgs=/\bargs\b/.test(body);
 const arrow=node.type==='ArrowFunctionExpression';
 functions[id]={id,node,module,name:sourceName,length:length<0?node.params.length:length,arrow,body,usesReceiver,usesArgs,slots:ctx.slots.count};return id;
}
function branchFunction(ctx,node){
 const id=branchHelpers.length,helper={...ctx,lines:[],receiver:'receiver'};branchHelpers.push(null);
 const conditional=node.type==='ConditionalExpression';
 const left=expr(helper,conditional?node.test:node.left);
 const condition=conditional?`s.truthy(${left})`:node.operator==='&&'?`s.truthy(${left})`:node.operator==='||'?`!s.truthy(${left})`:`rt.nullish(${left})`;
 function complete(next){
  if(next.type==='ConditionalExpression'||next.type==='LogicalExpression'){
   const child=branchFunction(helper,next);line(helper,`return @call(.always_tail, branch_${child}, .{ s, env, receiver, native_values });`);
  }else{const output=expr(helper,next);line(helper,`return ${output};`)}
 }
 line(helper,`if (${condition}) {`);complete(conditional?node.consequent:node.right);line(helper,'} else {');
 if(conditional)complete(node.alternate);else line(helper,`return ${left};`);
 line(helper,'}');branchHelpers[id]={body:helper.lines.join('\n'),source:ctx.module.file,start:node.start,end:node.end};return id;
}
function functionValue(ctx,node,inferred=''){
 const id=compileFunction(node,ctx.module,inferred,ctx.locals),f=functions[id];
 return value(ctx,`try rt.function(s, ${q(f.name)}, ${f.length}, f_${id}, env, ${ctx.receiver}, ${f.arrow})`);
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
   if(node.bigint)return value(ctx,`try rt.invoke(s, engine.intrinsic_bigint_constructor, c.pi_js_undefined(), &.{try s.text(${q(node.bigint)})})`);
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
   let callable,receiver='c.pi_js_undefined()';
   if(node.callee.type==='MemberExpression'&&!(node.callee.object.type==='Identifier'&&!ctx.locals.has(node.callee.object.name)&&local(ctx.module,node.callee.object.name)?.namespace)){const m=member(ctx,node.callee);receiver=m.object;callable=value(ctx,`try rt.key(s, ${m.object}, ${m.key})`)}else callable=expr(ctx,node.callee);
   const optional=node.optional;let output;
   if(optional){output=fresh('optional');line(ctx,`var ${output} = c.pi_js_undefined();`);line(ctx,`if (!rt.nullish(${callable})) {`)}
   let result;
   if(node.arguments.some(a=>a.type==='SpreadElement')){
    if(node.type==='NewExpression')throw Error('New spread');const array=value(ctx,'try s.array()');for(const a of node.arguments){const input=expr(ctx,a.type==='SpreadElement'?a.argument:a);line(ctx,`try rt.${a.type==='SpreadElement'?'spreadArray':'append'}(s, ${array}, ${input});`)}result=`try rt.invokeSpread(s, ${callable}, ${receiver}, ${array})`;
   }else{const args=node.arguments.map(a=>expr(ctx,a));result=node.type==='NewExpression'?`try rt.construct(s, ${callable}, &.{${args.join(', ')}})`:`try rt.invoke(s, ${callable}, ${receiver}, &.{${args.join(', ')}})`}
   if(optional){line(ctx,`${output} = ${result};`);line(ctx,'}');return output}return value(ctx,result);
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
   const id=branchFunction(ctx,node);return value(ctx,`try branch_${id}(s, env, ${ctx.receiver}, native_values)`);
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
  case 'ReturnStatement':{const output=expr(ctx,node.argument);line(ctx,`return c.JS_DupValue(engine.context, ${output});`);return}
  case 'ThrowStatement':{const output=expr(ctx,node.argument);line(ctx,`return rt.throwValue(s, ${output});`);return}
  case 'VariableDeclaration':for(const declaration of node.declarations)bindPattern(ctx,declaration.id,expr(ctx,declaration.init,declaration.id.name??''));return;
  case 'ExpressionStatement':{const result=expr(ctx,node.expression);discard(ctx,result);return}
  case 'IfStatement':{const test=expr(ctx,node.test);line(ctx,`if (s.truthy(${test})) {`);statement(ctx,node.consequent);if(node.alternate){line(ctx,'} else {');statement(ctx,node.alternate)}line(ctx,'}');return}
  case 'ForOfStatement':{
   const source=expr(ctx,node.right),iterator=fresh('loop');line(ctx,'{');line(ctx,`var ${iterator} = try rt.iterator(s, ${source});`);line(ctx,`defer ${iterator}.deinit();`);line(ctx,`errdefer ${iterator}.closePreserving();`);const item=fresh('item');line(ctx,`while (try ${iterator}.next()) |${item}| {`);line(ctx,`defer engine.freeValue(${item});`);bindPattern(ctx,node.left.declarations[0].id,item);statement(ctx,node.body);line(ctx,'}');line(ctx,'}');return;
  }
  case 'ForStatement':{
   line(ctx,'{');statement(ctx,node.init);line(ctx,'while (true) {');if(node.test){const test=expr(ctx,node.test);line(ctx,`if (!s.truthy(${test})) break;`)}statement(ctx,node.body);if(node.update){const result=expr(ctx,node.update);discard(ctx,result)}line(ctx,'}');line(ctx,'}');return;
  }
  case 'TryStatement':{
   if(node.handler||!returns(node.block)||returns(node.finalizer))throw Error('Unexpected try control shape');
   const id=tryHelpers.length,helper={...ctx,lines:[]};tryHelpers.push(null);statement(helper,node.block);tryHelpers[id]={body:helper.lines.join('\n')};
   const result=fresh('completion');line(ctx,`const ${result} = try_block_${id}(s, env, ${ctx.receiver}, native_values);`);line(ctx,`errdefer if (${result}) |returned| engine.freeValue(returned) else |_| {};`);statement(ctx,node.finalizer);line(ctx,`return ${result};`);return;
  }
  default:throw Error('Unlowered statement '+node.type+' in '+ctx.module.file);
 }
}
const initialize={module:null,locals:new Set(),lines:[],receiver:'c.pi_js_undefined()',slots:{count:0}};
for(const b of chosen.values())if(!b.external&&(b.init||b.node.type==='ClassDeclaration'))line(initialize,`try rt.declare(s, env, ${q(b.id)});`);
for(const b of chosen.values()){
 if(b.external){const operations=['EvaluateTemplateLiteral','EvaluateEnum','EvaluateIntersect','EvaluateType','EvaluateUnion','EvaluateDependent','EvaluateUnionFast'];const lengths=[1,1,1,1,1,3,1];
  const rhs=b.external==='evaluation'?`try rt.evaluationBinding(s, graph, ${q(b.name)}, ${operations.indexOf(b.name)}, ${lengths[operations.indexOf(b.name)]})`:`try s.get(graph, ${q(b.name)})`;line(initialize,`try rt.bind(s, env, ${q(b.id)}, ${rhs});`);
 }else if(b.node.type==='FunctionDeclaration'){
  const id=compileFunction(b.node,b.module,b.name),f=functions[id];line(initialize,`try rt.bind(s, env, ${q(b.id)}, try rt.function(s, ${q(f.name)}, ${f.length}, f_${id}, env, c.pi_js_undefined(), false));`);
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
const prelude='//! Generated native operations from pinned TypeBox1.3.27 authority.\n//! Static authoring only; no Source evaluation or runtime AST interpreter.\nconst rt = @import("native_typebox_operators_runtime.zig");\nconst c = rt.c;\n';
let native=prelude;
for(const f of functions){
 native+=`fn f_${f.id}(engine: *rt.Engine, ${f.usesReceiver&&!f.arrow?'receiver':'_'}: c.JSValue, ${f.usesArgs?'args':'_'}: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {\nvar scope: rt.Scope = .{ .engine = engine };\ndefer scope.deinit();\nconst s = &scope;\n${/\benv\b/.test(f.body)?'const env':'_'} = try rt.environment(s, roots[0]);\n`;
 if(f.arrow&&f.usesReceiver)native+='const receiver = roots[1];\n';if(f.slots)native+=`const native_values = try engine.gpa.alloc(c.JSValue, ${f.slots});\ndefer engine.gpa.free(native_values);\n`;native+=f.body+'\n}\n';
}
for(let i=0;i<tryHelpers.length;i++){const h=tryHelpers[i];native+=`fn try_block_${i}(s: *rt.Scope, env: c.JSValue, ${/\breceiver\b/.test(h.body)?'receiver':'_'}: c.JSValue, native_values: []c.JSValue) anyerror!c.JSValue {\nconst engine = s.engine;\n${h.body}\n}\n`}
for(let i=0;i<branchHelpers.length;i++){const h=branchHelpers[i];native+=`fn branch_${i}(s: *rt.Scope, ${/\benv\b/.test(h.body)?'env':'_'}: c.JSValue, ${/\breceiver\b/.test(h.body)?'receiver':'_'}: c.JSValue, ${/\bnative_values\b/.test(h.body)?'native_values':'_'}: []c.JSValue) anyerror!c.JSValue {\n${/\bengine\b/.test(h.body)?'const engine = s.engine;\n':''}${h.body}\n}\n`}
native+='pub fn create(engine: *rt.Engine, graph: c.JSValue) !c.JSValue {\nvar scope: rt.Scope = .{ .engine = engine };\ndefer scope.deinit();\nconst s = &scope;\nconst env = try rt.environment(s, c.pi_js_null());\n'+`const native_values = try engine.gpa.alloc(c.JSValue, ${initialize.slots.count});\ndefer engine.gpa.free(native_values);\n`+initialize.lines.join('\n')+'\nconst namespace = try s.object();\n';
for(const [name,b] of publicRoots)native+=`try s.put(namespace, ${q(name)}, try rt.get(s, env, ${q(b.id)}));\n`;
native+='return c.JS_DupValue(engine.context, namespace);\n}\n';
native+='pub fn install(engine: *rt.Engine, type_builder: c.JSValue, graph: c.JSValue) !void {\nconst namespace = try create(engine, graph);\ndefer engine.freeValue(namespace);\ntry @import("native_js_values.zig").spreadInto(engine, type_builder, namespace);\n}\n';
const nativePath=new URL('../../src/extensions/native_typebox_operators_production.zig',import.meta.url);
fs.writeFileSync(nativePath,native);
fs.writeFileSync(new URL('./lowering-map.json',import.meta.url),JSON.stringify({format:'compiled-native-source-span-map-v1',functions:functions.map(f=>({nativeCallback:`f_${f.id}`,source:f.module.file,start:f.node.start,end:f.node.end,sourceDeclarationSha256:crypto.createHash('sha256').update(f.module.source.slice(f.node.start,f.node.end)).digest('hex'),name:f.name,length:f.length,arrow:f.arrow,heapOperandSlots:f.slots})),nativeRawSha256:crypto.createHash('sha256').update(native).digest('hex'),tryHelpers:tryHelpers.length,operandStorage:'GPA-backed callback frame; borrowed JSValues remain traced by original Scope/cells',branches:branchHelpers.map((h,id)=>({nativeHelper:`branch_${id}`,source:h.source,start:h.start,end:h.end,tailChained:true}))},null,2)+'\n');
for(const file of new Set(initializationOrder.map(row=>row.module))){const selected=initializationOrder.filter(row=>row.module===file);for(let index=1;index<selected.length;index++)if(selected[index-1].start>=selected[index].start)throw Error('Original declaration order regression '+file)}
fs.writeFileSync(new URL('./initialization-order.json',import.meta.url),JSON.stringify({format:'actual-source-module-initialization-order-v1',lexicalBindings:initializationOrder.length,functionsHoisted:true,lexicalTdzPreserved:true,rows:initializationOrder},null,2)+'\n');
console.log(JSON.stringify({generatedFunctions:functions.length,tryHelpers:tryHelpers.length,bytes:Buffer.byteLength(native),nativeSha256:crypto.createHash('sha256').update(native).digest('hex')},null,2));

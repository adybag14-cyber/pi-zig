// Static case enumeration; no TypeBox imports or probe operations execute.
import fs from 'node:fs';
import crypto from 'node:crypto';
import {parse} from 'file:///C:/Users/adyba/AppData/Roaming/npm/node_modules/wrangler/node_modules/acorn/dist/acorn.mjs';
const input='C:/Users/adyba/pi-zig-typebox-operators-production-20261016/src/extensions/fixtures/typebox-operators-production.input.txt';
const bytes=fs.readFileSync(input),ast=parse(bytes.toString('utf8'),{ecmaVersion:'latest',sourceType:'script'});
const cases=[];
function evaluate(n,env){
 if(n.type==='Literal')return n.value;
 if(n.type==='Identifier'){if(!env.has(n.name))throw Error('Unknown case binding '+n.name);return env.get(n.name)}
 if(n.type==='TemplateLiteral')return n.quasis.reduce((s,q,i)=>s+q.value.cooked+(i<n.expressions.length?String(evaluate(n.expressions[i],env)):''),'');
 if(n.type==='UnaryExpression'&&n.operator==='typeof')return typeof evaluate(n.argument,env);
 if(n.type==='ArrayExpression')return n.elements.map(x=>evaluate(x,env));
 if(n.type==='ObjectExpression')return Object.fromEntries(n.properties.map(p=>[p.key.name??p.key.value,null]));
 if(n.type==='CallExpression'&&n.callee.type==='MemberExpression'&&n.callee.object.name==='Object'&&n.callee.property.name==='entries')return Object.entries(evaluate(n.arguments[0],env));
 throw Error('Unenumerable case expression '+n.type);
}
function bind(pattern,value,env){if(pattern.type==='Identifier')env.set(pattern.name,value);else if(pattern.type==='ArrayPattern')pattern.elements.forEach((p,i)=>p&&bind(p,value[i],env));else throw Error('Case binding '+pattern.type)}
function visit(node,env){
 if(!node)return;
 if(node.type==='FunctionDeclaration')return;
 if(node.type==='VariableDeclaration'){for(const d of node.declarations)if(d.id.type==='Identifier'&&d.init?.type==='ObjectExpression')env.set(d.id.name,evaluate(d.init,env));return}
 if(node.type==='ForOfStatement'){for(const value of evaluate(node.right,env)){const inner=new Map(env);bind(node.left.declarations[0].id,value,inner);visit(node.body,inner)}return}
 if(node.type==='CallExpression'&&node.callee.type==='Identifier'&&node.callee.name==='run'){cases.push(evaluate(node.arguments[0],env));return}
 if(node.type==='CallExpression'&&node.callee.type==='ArrowFunctionExpression'){visit(node.callee.body,env);return}
 if(node.type==='ArrowFunctionExpression'||node.type==='FunctionExpression')return;
 for(const [key,value]of Object.entries(node)){if(key==='start'||key==='end')continue;if(Array.isArray(value))value.forEach(x=>x&&typeof x==='object'&&visit(x,env));else if(value&&typeof value==='object')visit(value,env)}
}
visit(ast,new Map());
if(cases.length<300||new Set(cases).size!==cases.length)throw Error('Duplicate or undersized actual case inventory');
const result={status:'static_actual_probe_inventory_sealed',input, input_sha256:crypto.createHash('sha256').update(bytes).digest('hex'),count:cases.length,cases,TypeBox_executed:false,probe_operations_executed:false};
const output=new URL('./operator-probe-inventory-20261016.json',import.meta.url);
if(fs.existsSync(output))throw Error('Refuse sealed case inventory overwrite');
fs.writeFileSync(output,JSON.stringify(result,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({count:cases.length,input_sha256:result.input_sha256},null,2));

// Static authoring only: parses pinned source; never imports or runs TypeBox.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { parse } from 'file:///C:/Users/adyba/AppData/Roaming/npm/node_modules/wrangler/node_modules/acorn/dist/acorn.mjs';
const root='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/typebox/build';
const seeds=['type/engine/instantiate.mjs','type/engine/priority/priority.mjs','type/engine/with/instantiate.mjs','type/extends/extends.mjs','type/engine/template_literal/decode.mjs'];
const excluded=new Set(['system/memory/index.mjs','system/settings/index.mjs','type/engine/evaluate/evaluate.mjs']);
const modules=new Map(),kinds={},examples={};
function scan(relative){
  relative=relative.replaceAll('\\','/'); if(modules.has(relative)||excluded.has(relative))return;
  const filename=path.join(root,relative),source=fs.readFileSync(filename,'utf8');
  const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});
  const deps=[];modules.set(relative,{relative,bytes:Buffer.byteLength(source),sha256:crypto.createHash('sha256').update(source).digest('hex'),deps,ast});
  function walk(node){if(!node||typeof node!=='object')return;if(node.type){kinds[node.type]=(kinds[node.type]||0)+1;examples[node.type]??={relative,text:source.slice(node.start,node.end).slice(0,200)}}for(const value of Object.values(node)){if(Array.isArray(value))value.forEach(walk);else if(value&&typeof value==='object')walk(value)}}walk(ast);
  for(const stmt of ast.body){if(stmt.source){if(!stmt.source.value.startsWith('.'))throw Error('External source import '+stmt.source.value);const dep=path.posix.normalize(path.posix.join(path.posix.dirname(relative),stmt.source.value));deps.push(dep);scan(dep)}}
}
seeds.forEach(scan);
const report={package:'typebox',version:'1.3.27',root,seeds,externalSharedBindings:[...excluded],modules:[...modules.values()].map(({ast,...row})=>row),moduleCount:modules.size,syntax:kinds,examples};
fs.writeFileSync(new URL('./authority-closure.json',import.meta.url),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({modules:modules.size,bytes:[...modules.values()].reduce((n,m)=>n+m.bytes,0),syntax:kinds},null,2));

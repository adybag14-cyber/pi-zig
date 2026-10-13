import { spawn } from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
const evidence = path.dirname(import.meta.filename);
const binary = path.join(evidence,'env-listfiles-oracle-target-e6220e1-20261013/debug/pi-env.exe');
const root = path.join(evidence,'env-listfiles-oracle-tree-e6220e1-20261013');
await fs.mkdir(root, { recursive: true });
const files = {
 'home/.gitconfig':'[core]\nexcludesFile = ~/global-ignore\n',
 'home/global-ignore':'global.txt\n*.global\n',
 'project/.git/HEAD':'ref: refs/heads/main\n',
 'project/.git/info/exclude':'keep.txt\nexcluded.txt\n',
 'project/.gitignore':'out/\n*.log\n!keep.txt\n!.visible\n# comment\n\\#literal\n\\!literal\ntrailing\\ \nrange[0-2].txt\nbrace{a,b}.txt\na/**/drop\n',
 'project/.ignore':'ignored-by-dot-ignore\n',
 'project/.hidden/x':'', 'project/.visible':'', 'project/.git-file':'',
 'project/A.txt':'','project/a/b/c.txt':'','project/a/drop':'','project/a/n/drop':'','project/a/z.txt':'','project/b.txt':'',
 'project/keep.txt':'','project/excluded.txt':'','project/out/x.js':'','project/global.txt':'','project/sub/global.txt':'',
 'project/sub/.gitignore':'!keep.txt\n','project/sub/keep.txt':'','project/sub/drop.log':'','project/node_modules/m/i.js':'',
 'project/#literal':'','project/!literal':'','project/trailing ':'','project/range1.txt':'','project/range4.txt':'','project/bracea.txt':'','project/bracec.txt':'','project/ignored-by-dot-ignore':'',
 'project/nested/.git/HEAD':'ref: refs/heads/main\n','project/nested/keep.txt':'','project/nested/drop.log':'',
 'plain/.gitignore':'*.log\n','plain/keep.log':'','plain/normal':'',
 'jj/.jj/repo':'','jj/.gitignore':'*.log\n','jj/drop.log':'','jj/keep':'',
 'bounds/a':'','bounds/b':'','bounds/c':'',
};
const directories = ['project/empty','empty'];
for (const [name,content] of Object.entries(files)) { const full=path.join(root,name); await fs.mkdir(path.dirname(full),{recursive:true}); await fs.writeFile(full,content); }
for (const name of directories) await fs.mkdir(path.join(root,name),{recursive:true});
const token=crypto.randomBytes(16).toString('hex');
const env={...process.env,HOME:path.join(root,'home'),USERPROFILE:path.join(root,'home')};
for (const key of ['XDG_CONFIG_HOME','GIT_CONFIG_GLOBAL','GIT_CONFIG_SYSTEM']) delete env[key];
const child=spawn(binary,['serve','--token',token],{stdio:['pipe','pipe','pipe'],env,windowsHide:true});
let pending=Buffer.alloc(0), synced=false, nextId=1, stderr='';
const waiting=new Map();
child.stderr.on('data',chunk=>stderr+=chunk);
child.stdout.on('data',chunk=>{
 pending=Buffer.concat([pending,chunk]);
 if(!synced){ const end=pending.indexOf(10); if(end<0)return; assert.equal(pending.subarray(0,end).toString().trim(),`PI-ENV ${token}`); pending=pending.subarray(end+1); synced=true; }
 while(pending.length>=4 && pending.length>=4+pending.readUInt32BE(0)){
  const n=pending.readUInt32BE(0),body=pending.subarray(4,4+n);pending=pending.subarray(4+n);
  const kind=body[0],id=body.readUInt32BE(1),j=body.readUInt32BE(5),json=JSON.parse(body.subarray(9,9+j));
  if(kind===6){send(6,id,{});continue;}
  const resolve=waiting.get(id);if(resolve){waiting.delete(id);resolve({kind,json,payload:body.subarray(9+j)});}
 }
});
function send(kind,id,json){const bytes=Buffer.from(JSON.stringify(json)),frame=Buffer.alloc(13+bytes.length);frame.writeUInt32BE(9+bytes.length,0);frame[4]=kind;frame.writeUInt32BE(id,5);frame.writeUInt32BE(bytes.length,9);bytes.copy(frame,13);child.stdin.write(frame);}
function request(json){const id=nextId++;return new Promise((resolve,reject)=>{waiting.set(id,resolve);send(1,id,json);setTimeout(()=>{if(waiting.delete(id))reject(Error('reference request timed out'));},10000).unref();});}
const hello=await request({op:'hello',protocol:1});assert(hello.json.features.includes('listFiles'));
const specifications = [
 ['default','project',{}],['hidden','project',{hidden:false}],['no-ignore','project',{gitignore:false}],
 ['exclude','project',{exclude:['node_modules','a','nested']}],['subtree','project/sub',{}],['nested-repo','project/nested',{}],
 ['outside-repo','plain',{}],['jj-repo','jj',{}],['empty','empty',{}],
 ['entries2','bounds',{maxEntries:2}],['entries3','bounds',{maxEntries:3}],['entries0','bounds',{maxEntries:0}],
 ['bytes6','bounds',{maxBytes:6}],['bytes2','bounds',{maxBytes:2}],['timeout0','bounds',{timeoutMs:0}],
 ['missing','missing',{}],['file','bounds/a',{}],['bad-count','bounds',{maxEntries:-1}],['fractional','bounds',{timeoutMs:1.5}],['bad-exclude','bounds',{exclude:[4]}],
];
const cases=[];
for(const [name,relative,options] of specifications){const reply=await request({op:'listFiles',path:path.join(root,relative),...options});cases.push({name,path:relative,options,kind:reply.kind,json:reply.kind===2?reply.json:{code:reply.json.code},payload:reply.payload.toString('base64')});}
child.stdin.end(); await new Promise(resolve=>child.on('exit',resolve));
const packet={upstream:'e6220e1316f86af818a0ccbfe1c09d7e918b41cf',binary_sha256:crypto.createHash('sha256').update(await fs.readFile(binary)).digest('hex'),files,directories,cases,hello:hello.json,stderr};
await fs.writeFile(path.join(evidence,'env-listfiles-oracle-e6220e1-20261013.json'),JSON.stringify(packet,null,2)+'\n');
console.log(JSON.stringify({cases:cases.length,binary_sha256:packet.binary_sha256,hello:hello.json.features,terminal:'passed'}));

// Prospective Git-only Source gate. Prepared, never executed in this packet.
// Root must grant a bounded owner process and provide fresh complete seals.
import {readFileSync,realpathSync,existsSync,appendFileSync,statSync} from 'node:fs';
import {resolve,dirname,basename,join,relative,isAbsolute,sep} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {registerHooks} from 'node:module';
const expectedHead='4dd2b149d155d7369de16ea4dc77c84e9f5ffb24';
const originalRuntimeManifestSha256='38223db79be24c7f9f5833a662d3c73ff2531f78489699dbf87f9f52a9b4bfba';
const container=realpathSync(resolve(dirname(fileURLToPath(import.meta.url)),'../../../..'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const inside=(root,path)=>{const rel=relative(root,path);return rel===''||(!rel.startsWith('..'+sep)&&rel!=='..'&&!isAbsolute(rel))};
const contained=path=>{const absolute=resolve(container,path);if(!inside(container,absolute))throw Error('Reference path outside project container');return absolute};
const realContained=path=>{const actual=realpathSync(contained(path));if(!inside(container,actual))throw Error('Resolved reference escaped project container');return actual};
const workspaceBytes=readFileSync(join(container,'.pi-zig-workspace.json')),relocationBytes=readFileSync(join(container,'path-relocations.json'));
const workspace=JSON.parse(workspaceBytes),relocation=JSON.parse(relocationBytes);
if(workspace.integration_upstream_commit!==expectedHead)throw Error('Prospective Source head requires explicit refresh');
if(workspace.runtime_status==='recovery_pending'||workspace.all_agent_jobs_held_for_revalidation===true)throw Error('Full recovery/revalidation remains held');
const planPath=contained(process.env.PI_ZIG_REFERENCE_PLAN||'');
if(!process.env.PI_ZIG_REFERENCE_PLAN)throw Error('Root-admitted fresh reference plan required');
const planBytes=readFileSync(planPath);
if(!/^[a-fA-F0-9]{64}$/.test(process.env.PI_ZIG_REFERENCE_PLAN_SHA256||'')||digest(planBytes)!==process.env.PI_ZIG_REFERENCE_PLAN_SHA256.toLowerCase())throw Error('Fresh plan digest required');
const plan=JSON.parse(planBytes);
if(plan.schema!==1||plan.sourceHead!==expectedHead||plan.nodeVersion!=='v24.14.0'||process.version!==plan.nodeVersion)throw Error('Pinned prospective authority mismatch');
if(digest(workspaceBytes)!==plan.workspaceSha256?.toLowerCase()||digest(relocationBytes)!==plan.relocationsSha256?.toLowerCase())throw Error('Container metadata changed after admission');
const sourceRoot=realContained(workspace.upstream_repository),runtimeRoot=realContained(workspace.runtime),evidenceRoot=realContained(workspace.evidence);
if(!inside(evidenceRoot,planPath))throw Error('Prospective plan must be in evidence');
function repositoryHead(root){let git=join(root,'.git');if(!statSync(git).isDirectory()){const line=readFileSync(git,'utf8').trim();if(!line.startsWith('gitdir: '))throw Error('Unsupported Source Git metadata');git=realContained(resolve(root,line.slice(8)))}const head=readFileSync(join(git,'HEAD'),'utf8').trim();if(/^[a-f0-9]{40}$/.test(head))return head;if(!head.startsWith('ref: '))throw Error('Unsupported Source HEAD');const ref=head.slice(5);let common=git;if(existsSync(join(git,'commondir')))common=realContained(resolve(git,readFileSync(join(git,'commondir'),'utf8').trim()));for(const base of [git,common])if(existsSync(join(base,ref)))return readFileSync(join(base,ref),'utf8').trim();const packed=join(common,'packed-refs');if(existsSync(packed))for(const line of readFileSync(packed,'utf8').split(/\r?\n/)){const [sha,name]=line.split(' ');if(name===ref&&/^[a-f0-9]{40}$/.test(sha))return sha}throw Error('Source ref absent')}
if(repositoryHead(sourceRoot)!==expectedHead)throw Error('Official Source checkout head changed');
function relocated(path){
 const normalized=resolve(path);if(inside(container,normalized))return normalized;
 const mappings=[...relocation.mappings].sort((a,b)=>b.old.length-a.old.length);
 for(const item of mappings){if(normalized===resolve(item.old)||inside(resolve(item.old),normalized))return contained(resolve(item.new,relative(resolve(item.old),normalized)))}
 throw Error('Historical path has no explicit relocation: '+path);
}
function sealedBytes(descriptor){
 if(!descriptor||typeof descriptor.path!=='string'||!/^[a-fA-F0-9]{64}$/.test(descriptor.sha256||''))throw Error('Complete seal descriptor required');
 const path=realContained(descriptor.path),bytes=readFileSync(path);if(digest(bytes)!==descriptor.sha256.toLowerCase())throw Error('Seal changed: '+path);return {path,bytes};
}
const frozen=new Map(),roles=new Map();
function manifest(descriptor,role,requiredCount){
 const {bytes}=sealedBytes(descriptor),rows=JSON.parse(bytes);
 if(!Array.isArray(rows)||rows.length!==(requiredCount??descriptor.records)||rows.length===0)throw Error('Complete '+role+' record count mismatch');
 const seen=new Set();
 for(const row of rows){if(typeof row.path!=='string'||!/^[a-fA-F0-9]{64}$/.test(row.sha256||''))throw Error('Malformed authority row');const path=realContained(relocated(row.path));if(seen.has(path))throw Error('Duplicate authority path');seen.add(path);
  if(role==='source'&&!inside(sourceRoot,path))throw Error('Source manifest escaped official checkout');
  if(role==='runtime'&&!inside(runtimeRoot,path))throw Error('Runtime manifest escaped recovery root');
  const hash=digest(readFileSync(path));if(hash!==row.sha256.toLowerCase())throw Error('Pinned '+role+' byte mismatch: '+path);
  if(frozen.has(path)&&frozen.get(path)!==hash)throw Error('Conflicting authority roles');frozen.set(path,hash);if(!roles.has(path))roles.set(path,new Set());roles.get(path).add(role);
 }
 return rows.length;
}
const recovery=sealedBytes(plan.recoveryReceipt);
const receipt=JSON.parse(recovery.bytes);
if(plan.originalRuntimeManifest.sha256?.toLowerCase()!==originalRuntimeManifestSha256||receipt.originalManifestSha256?.toLowerCase()!==originalRuntimeManifestSha256||receipt.originalRecords!==31064||receipt.matchedRecords!==31064||receipt.missingRecords!==0||receipt.mismatchedRecords!==0)throw Error('Complete original runtime recovery receipt required');
const counts={source:manifest(plan.sourceManifest,'source'),runtime:manifest(plan.originalRuntimeManifest,'runtime',31064),node:manifest(plan.originalNodeManifest,'node',1774),controls:manifest(plan.controlManifest,'control'),candidate:manifest(plan.candidateManifest,'candidate')};
const executable=realpathSync(process.execPath);if(!roles.get(executable)?.has('node'))throw Error('Running Node executable lacks original tool-tree seal');
const absent=JSON.parse(sealedBytes(plan.absenceManifest).bytes);if(!Array.isArray(absent)||absent.length!==84)throw Error('Complete actual absence inventory required');
for(const row of absent){const path=relocated(row.path);if(existsSync(path))throw Error('Pinned actual absence changed: '+path)}
const freshEvidencePath=path=>{const lexical=contained(path),parent=realContained(dirname(lexical)),actual=join(parent,basename(lexical));if(!inside(evidenceRoot,actual)||existsSync(actual))throw Error('Fresh evidence path required');return actual};
const tracePath=freshEvidencePath(plan.tracePath);
function record(row){appendFileSync(tracePath,JSON.stringify(row)+'\n')}
const observed=new Set(),dataInputs=new Set();
function observe(url){
 if(url.startsWith('node:'))return;
 if(url.startsWith('data:')){if(!dataInputs.has(url))throw Error('Unsealed data module');return}
 if(!url.startsWith('file:'))throw Error('Unsupported reference module URL');
 const path=realContained(fileURLToPath(url));
 if(inside(runtimeRoot,path)&&!inside(join(runtimeRoot,'node_modules'),path))throw Error('Historical workspace implementation escaped current Source');
 if(!frozen.has(path))throw Error('Unmanifested reference module: '+path);
 const hash=digest(readFileSync(path));if(hash!==frozen.get(path))throw Error('Reference module changed after complete seal: '+path);
 if(!observed.has(path)){observed.add(path);record({kind:'observed-module',path,sha256:hash,roles:[...roles.get(path)]})}
}
const hostedPath=join(runtimeRoot,'node_modules','hosted-git-info','lib','index.js');
registerHooks({resolve(specifier,context,next){
 // This packet executes only the original Git utility. It does not pretend to
 // migrate the wider SDK workspace resolver; an unexpected workspace fails.
 if(specifier.startsWith('@earendil-works/'))throw Error('Git-only observer requires separately reviewed workspace map');
 const result=specifier==='hosted-git-info'?{url:pathToFileURL(hostedPath).href,shortCircuit:true}:next(specifier,context);observe(result.url);return result;
}});
observe(import.meta.url);
export function checkedInput(path){const resolved=realContained(path);if(!roles.get(resolved)?.has('control'))throw Error('Input is not in the complete control seal');const bytes=readFileSync(resolved);if(digest(bytes)!==frozen.get(resolved))throw Error('Control input changed');const url='data:text/javascript,'+encodeURIComponent(bytes.toString('utf8'));dataInputs.add(url);record({kind:'control-input',path:resolved,sha256:digest(bytes)});return {bytes,url,path:resolved}}
export function outputPath(path){return freshEvidencePath(path)}
export function checkedSource(path,sha256){const resolved=realContained(path);if(!roles.get(resolved)?.has('source')||digest(readFileSync(resolved))!==sha256.toLowerCase())throw Error('Original Source byte check failed');return resolved}
export function checkedDependency(path,sha256){const resolved=realContained(path);if(!roles.get(resolved)?.has('runtime')||digest(readFileSync(resolved))!==sha256.toLowerCase())throw Error('Original dependency byte check failed');return resolved}
export const authority={container,sourceRoot,runtimeRoot,evidenceRoot,sourceHead:expectedHead,counts,planPath,tracePath,hostedPath};

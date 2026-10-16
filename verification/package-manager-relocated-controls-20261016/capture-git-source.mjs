// Prospective capture runner only. No execution was performed while preparing it.
import {readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import nodeUrl from 'node:url';
import {createHash} from 'node:crypto';
import {authority,checkedInput,outputPath,checkedSource,checkedDependency} from './reference-gate.mjs';
const source=checkedSource(join(authority.sourceRoot,'packages/coding-agent/src/utils/git.ts'),'BFF4590AEFA988BA625026769AC5AD02F02558D59BD7D566F4728E1EE4DA1DA9');
const dependency=checkedDependency(authority.hostedPath,'37F3C1042F5202D6E10EE1B39797A281E8BA1D3620193427A51C89B55101BA77');
const input=checkedInput(process.argv[3]),output=outputPath(process.argv[2]),caseId=process.argv[4];
const {parseGitUrl}=await import(pathToFileURL(source).href),{default:hosted}=await import(pathToFileURL(dependency).href);
globalThis.GitAPI={parseGitUrl,hosted,nodeUrl,caseId,advanceJob:()=>new Promise(resolve=>setImmediate(resolve)),collectGarbage:typeof globalThis.gc==='function'?globalThis.gc:undefined};
await import(input.url);
if(gitSourceHostedComplete!==true||!Array.isArray(gitSourceHostedRows)||new Set(gitSourceHostedRows.map(row=>row.name)).size!==gitSourceHostedRows.length)throw Error('Incomplete original observations');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
writeFileSync(output,JSON.stringify({status:'raw_reference_observation_pending_independent_post_close',sourceHead:authority.sourceHead,sourceSha256:sha(readFileSync(source)),dependencySha256:sha(readFileSync(dependency)),inputSha256:sha(input.bytes),caseId,cases:gitSourceHostedRows.length,rows:gitSourceHostedRows,authorityCounts:authority.counts,planPath:authority.planPath,tracePath:authority.tracePath},null,2)+'\n',{flag:'wx'});

// Prepared observer only. Requires a new Root-admitted full Source/control/
// candidate/runtime seal and bounded owner process. Has not been executed.
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import nodeUrl from 'node:url';
const observer='C:/Users/adyba/pi-upstream-audit-0fbdbd3-20261016/source0fb-observe.mjs';
if(!process.execArgv.some(value=>value.replaceAll('\\','/').includes(observer)))throw Error('Pinned full Source observer preload required');
if(!process.env.PI_SOURCE_ORACLE_CONTROL_MANIFEST)throw Error('Full immutable input/control seal required');
if(process.version!=='v24.14.0')throw Error('Pinned Node24.14.0 required');
const source='C:/Users/adyba/pi-upstream-source-0fbdbd3-20261016/packages/coding-agent/src/utils/git.ts';
const dependency='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/hosted-git-info/lib/index.js';
const sha=value=>createHash('sha256').update(value).digest('hex');
if(sha(readFileSync(source))!=='bff4590aefa988ba625026769ac5ad02f02558d59bd7d566f4728e1ee4da1da9')throw Error('Original Git parser changed');
if(sha(readFileSync(dependency))!=='37f3c1042f5202d6e10ee1b39797a281e8ba1d3620193427a51c89b55101ba77')throw Error('Pinned hosted-git-info changed');
const {parseGitUrl}=await import(nodeUrl.pathToFileURL(source).href);
const {default:hosted}=await import(nodeUrl.pathToFileURL(dependency).href);
globalThis.GitAPI={parseGitUrl,hosted,nodeUrl};
const input=readFileSync(process.argv[3]);await import('data:text/javascript,'+encodeURIComponent(input.toString('utf8')));
if(gitSourceHostedComplete!==true||!Array.isArray(gitSourceHostedRows)||new Set(gitSourceHostedRows.map(row=>row.name)).size!==gitSourceHostedRows.length)throw Error('Incomplete genuine Git controls');
writeFileSync(process.argv[2],JSON.stringify({sourceHead:'0fbdbd3f8ab1876ac260c0f08226a400759323b8',sourceSha256:sha(readFileSync(source)),dependencySha256:sha(readFileSync(dependency)),inputSha256:sha(input),cases:gitSourceHostedRows.length,rows:gitSourceHostedRows},null,2)+'\n');

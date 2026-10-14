import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { join } from 'node:path';
const root = 'C:/Users/adyba/pi-upstream-source-b45e0eb-20261014';
const head = 'b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb';
const hash = path => createHash('sha256').update(readFileSync(path)).digest('hex');
const [output, inputPath, frozenPath] = process.argv.slice(2);
const frozenHash = hash(frozenPath);
function verify() {
  if (hash(frozenPath) !== frozenHash) throw Error('Frozen manifest inventory drift');
  return JSON.parse(readFileSync(frozenPath, 'utf8')).map(manifest => {
    if (hash(manifest.path) !== manifest.sha256.toLowerCase()) throw Error('Manifest drift ' + manifest.path);
    const rows = JSON.parse(readFileSync(manifest.path, 'utf8'));
    for (const row of rows) if (hash(row.path) !== row.sha256.toLowerCase()) throw Error('Frozen file drift ' + row.path);
    return { manifest: manifest.name, count: rows.length, drift: 0 };
  });
}
const before = verify();
const {default:core}=await import(pathToFileURL(join(root,'node_modules/highlight.js/lib/core.js')).href);
globalThis.highlightCoreAPI=core;
globalThis.highlightSyntaxAPI=await import(pathToFileURL(join(root,'packages/coding-agent/src/utils/syntax-highlight.ts')).href);
const {createRequire}=await import('node:module');
const actualRequire=createRequire(pathToFileURL(join(root,'packages/coding-agent/package.json')));
const eagerNames=['python','java','go','javascript','json','cpp','typescript','php','ruby','c','csharp','nix','bash','rust','scala','kotlin','swift','dart','groovy','perl','lua'];
globalThis.highlightGrammarFactories=Object.fromEntries(eagerNames.map(name=>[name,actualRequire('highlight.js/lib/languages/'+name+'.js')]));
if(typeof globalThis.gc!=='function')throw Error('Required actual Node GC unavailable');
globalThis.collectInheritanceGarbage=async()=>{await new Promise(resolve=>setImmediate(resolve));globalThis.gc();await new Promise(resolve=>setImmediate(resolve));};
const input = readFileSync(inputPath, 'utf8');
await import('data:text/javascript,' + encodeURIComponent(input));
await collectInheritanceGarbage();
if (sdkHighlightCoreRows.length !== 74) throw Error('Original74 capture inventory mismatch');
const modulePath = `C:/Users/adyba/pi-zig-update-evidence-20261003/sdk-source-b45-modules-${process.pid}-0-20261014.jsonl`;
const observedModules = readFileSync(modulePath, 'utf8').trim().split('\n').map(JSON.parse);
for (const row of observedModules.filter(row => row.kind === 'observed-module')) if (hash(row.path) !== row.sha256) throw Error('Observed module drift');
writeFileSync(output, JSON.stringify({ sourceHead: head, actualNodeGcExecuted: true, cases: sdkHighlightCoreRows.length, inputSha256: hash(inputPath), platform: process.platform, node: { version: process.version, path: process.execPath, sha256: hash(process.execPath), execArgv: process.execArgv }, before, after: verify(), scope: 'Unchanged actual highlight.js10.7.3 inherit; actual eager21 factories and63 scanner+syntax outputs, common-mode JSON graph and private classes obtained from genuine scanner callbacks without Source rewriting, actual Node GC. No Source body rewriting. Historical typed catalog metadata only; latest generated catalog unqualified.', rows: sdkHighlightCoreRows, observedModules }, null, 2));


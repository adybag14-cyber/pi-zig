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
const actualDiff=await import(pathToFileURL(join(root,'node_modules/diff/libesm/index.js')).href);
const sourceEdit=await import(pathToFileURL(join(root,'packages/coding-agent/src/core/tools/edit-diff.ts')).href);
const sourceRender=await import(pathToFileURL(join(root,'packages/coding-agent/src/modes/interactive/components/diff.ts')).href);
const sourceTheme=await import(pathToFileURL(join(root,'packages/coding-agent/src/modes/interactive/theme/theme.ts')).href);
sourceTheme.initTheme('dark',false);
globalThis.editDiffAPI={diffWords:actualDiff.diffWords,diffLines:actualDiff.diffLines,generateDiffString:sourceEdit.generateDiffString,applyEditsToNormalizedContent:sourceEdit.applyEditsToNormalizedContent,renderDiff:sourceRender.renderDiff};
if(typeof globalThis.gc!=='function')throw Error('Required actual Node GC unavailable');
globalThis.collectInheritanceGarbage=async()=>{await new Promise(resolve=>setImmediate(resolve));globalThis.gc();await new Promise(resolve=>setImmediate(resolve));};
const input = readFileSync(inputPath, 'utf8');
await import('data:text/javascript,' + encodeURIComponent(input));
await collectInheritanceGarbage();
if (sdkEditDiffRows.length !== 54) throw Error('OriginalEditDiff54 capture inventory mismatch');
const modulePath = `C:/Users/adyba/pi-zig-update-evidence-20261003/sdk-source-b45-modules-${process.pid}-0-20261014.jsonl`;
const observedModules = readFileSync(modulePath, 'utf8').trim().split('\n').map(JSON.parse);
for (const row of observedModules.filter(row => row.kind === 'observed-module')) if (hash(row.path) !== row.sha256) throw Error('Observed module drift');
writeFileSync(output, JSON.stringify({ sourceHead: head, actualNodeGcExecuted: true, cases: sdkEditDiffRows.length, inputSha256: hash(inputPath), platform: process.platform, node: { version: process.version, path: process.execPath, sha256: hash(process.execPath), execArgv: process.execArgv }, before, after: verify(), scope: 'Unchanged actual jsdiff8.0.4 words/lines and actual b45 edit diff display, rendering with genuine dark Theme and normalized multi-edits, actual Node GC. No Source body rewriting. Historical typed catalog metadata only; latest generated catalog unqualified.', rows: sdkEditDiffRows, observedModules }, null, 2));


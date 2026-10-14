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
const render = await import(pathToFileURL(join(root, 'packages/coding-agent/src/core/tools/render-utils.ts')).href);
const prompt = await import(pathToFileURL(join(root, 'packages/coding-agent/src/core/prompt-templates.ts')).href);
globalThis.readPromptAPI = { formatReadLineRange: render.formatReadLineRange, parseCommandArgs: prompt.parseCommandArgs, substituteArgs: prompt.substituteArgs, expandPromptTemplate: prompt.expandPromptTemplate };
const input = readFileSync(inputPath, 'utf8');
await import('data:text/javascript,' + encodeURIComponent(input));
if (sdkReadPromptRows.length !== 54) throw Error('Original54 capture inventory mismatch');
const modulePath = `C:/Users/adyba/pi-zig-update-evidence-20261003/sdk-source-b45-modules-${process.pid}-0-20261014.jsonl`;
const observedModules = readFileSync(modulePath, 'utf8').trim().split('\n').map(JSON.parse);
for (const row of observedModules.filter(row => row.kind === 'observed-module')) if (hash(row.path) !== row.sha256) throw Error('Observed module drift');
writeFileSync(output, JSON.stringify({ sourceHead: head, cases: sdkReadPromptRows.length, inputSha256: hash(inputPath), platform: process.platform, node: { version: process.version, path: process.execPath, sha256: hash(process.execPath), execArgv: process.execArgv }, before, after: verify(), scope: 'Unchanged genuine b45 module exports; actual read-range numeric parsing and live callbacks; quoted-empty/Unicode prompt parsing, defaults, slices and expansion. No Source body rewriting. Historical typed catalog metadata only; latest generated catalog unqualified.', rows: sdkReadPromptRows, observedModules }, null, 2));

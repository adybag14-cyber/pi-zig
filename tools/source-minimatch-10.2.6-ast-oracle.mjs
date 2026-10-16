// Original AST dependency controls only. Do not run during another runtime lease.
import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
const [runtime, source, output] = process.argv.slice(2);
if (!runtime || !source || !output) throw Error('usage: node source-minimatch-10.2.6-ast-oracle.mjs RUNTIME SOURCE OUTPUT');
if (process.env.__MINIMATCH_TESTING_PLATFORM__) throw Error('platform override is not allowed for original evidence');
const root = resolve(import.meta.dirname, '..');
const files = {
  minimatch: join(runtime, 'node_modules/minimatch/dist/esm/index.js'),
  ast: join(runtime, 'node_modules/minimatch/dist/esm/ast.js'),
  classes: join(runtime, 'node_modules/minimatch/dist/esm/brace-expressions.js'),
  assertValid: join(runtime, 'node_modules/minimatch/dist/esm/assert-valid-pattern.js'),
  escape: join(runtime, 'node_modules/minimatch/dist/esm/escape.js'),
  unescape: join(runtime, 'node_modules/minimatch/dist/esm/unescape.js'),
  braces: join(runtime, 'node_modules/brace-expansion/dist/esm/index.js'),
  balanced: join(runtime, 'node_modules/balanced-match/dist/esm/index.js'),
  packageManager: join(source, 'packages/coding-agent/src/core/package-manager.ts'),
  modelResolver: join(source, 'packages/coding-agent/src/core/model-resolver.ts'),
  cases: join(root, 'src/extensions/fixtures/minimatch-10.2.6.cases.json'),
};
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const base = JSON.parse(await readFile(join(root, 'verification/minimatch-10.2.6-source-only-20261016.json'), 'utf8'));
const hashes = {};
for (const row of base.sourceFiles) {
  hashes[row.name] = sha(await readFile(files[row.name]));
  if (hashes[row.name] !== row.sha256) throw Error(`original authority drift: ${row.name}`);
}
const supplement = JSON.parse(await readFile(join(root, 'verification/minimatch-10.2.6-supplement-source-only-20261016.json'), 'utf8'));
for (const [suite, record] of Object.entries(supplement.suites)) {
  if (sha(await readFile(join(root, `src/extensions/fixtures/minimatch-10.2.6.${suite}.cases.json`))) !== record.sha256) throw Error(`earlier supplementary input drift: ${suite}`);
}
const receipt = JSON.parse(await readFile(join(root, 'verification/minimatch-10.2.6-ast-source-only-20261016.json'), 'utf8'));
const input = await readFile(join(root, 'src/extensions/fixtures/minimatch-10.2.6.ast.cases.json'));
const casesSha256 = sha(input);
if (casesSha256 !== receipt.casesSha256) throw Error('AST input identity drift');
const { minimatch } = await import(pathToFileURL(files.minimatch).href);
const rows = JSON.parse(input).map(row => {
  try { return { id: row.id, result: minimatch(row.path, row.pattern, row.options) }; }
  catch (error) { return { id: row.id, errorName: error.name }; }
});
await writeFile(resolve(output), JSON.stringify({
  kind: 'original-minimatch-ast-control', baseCommit: '7af3116b051bf6f087e4c5a40ed35bbdb6ca4af9',
  sourceHead: base.sourceHead, minimatchVersion: '10.2.6', casesSha256,
  node: process.version, platform: process.platform, hashes, rows,
}, null, 2) + '\n', { flag: 'wx' });

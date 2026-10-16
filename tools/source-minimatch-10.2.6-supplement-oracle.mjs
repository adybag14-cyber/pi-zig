// Original dependency control only; no native algorithm produces these rows.
// Do not execute while another native/runtime lease is active.
import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
const [runtime, source, output, suite = 'linebreak-globstar'] = process.argv.slice(2);
if (!runtime || !source || !output || !['linebreak-globstar', 'astral-classes', 'peer-regressions'].includes(suite)) throw Error('usage: node source-minimatch-10.2.6-supplement-oracle.mjs RUNTIME SOURCE OUTPUT [linebreak-globstar|astral-classes|peer-regressions]');
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
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const base = JSON.parse(await readFile(join(root, 'verification/minimatch-10.2.6-source-only-20261016.json'), 'utf8'));
const hashes = {};
for (const row of base.sourceFiles) {
  hashes[row.name] = hash(await readFile(files[row.name]));
  if (hashes[row.name] !== row.sha256) throw Error(`original authority drift: ${row.name}`);
}
const receipt = JSON.parse(await readFile(join(root, 'verification/minimatch-10.2.6-supplement-source-only-20261016.json'), 'utf8'));
const caseBytes = await readFile(join(root, `src/extensions/fixtures/minimatch-10.2.6.${suite}.cases.json`));
const casesSha256 = hash(caseBytes);
if (receipt.suites[suite].sha256 !== casesSha256) throw Error('supplement case identity drift');
const { minimatch } = await import(pathToFileURL(files.minimatch).href);
const cases = JSON.parse(caseBytes);
const rows = cases.map(row => {
  try { return { id: row.id, result: minimatch(row.path, row.pattern, row.options) }; }
  catch (error) { return { id: row.id, errorName: error.name }; }
});
await writeFile(resolve(output), JSON.stringify({
  kind: 'original-dependency-control-supplement', baseCommit: 'd849736a0c7d2d73bf63711b6f99a6bd76469b06',
  sourceHead: base.sourceHead, minimatchVersion: '10.2.6', suite,
  node: process.version, platform: process.platform, casesSha256, hashes, rows,
}, null, 2) + '\n', { flag: 'wx' });

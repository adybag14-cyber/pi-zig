// Original dependency control only. Never imported by the native implementation.
// Run only after the global native runtime lease permits Node controls.
import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
const [runtime, source, output] = process.argv.slice(2);
if (!runtime || !source || !output) throw Error('usage: node source-minimatch-10.2.6-oracle.mjs RUNTIME SOURCE OUTPUT');
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
  caller: join(source, 'packages/coding-agent/src/core/package-manager.ts'),
  modelResolver: join(source, 'packages/coding-agent/src/core/model-resolver.ts'),
  cases: join(root, 'src/extensions/fixtures/minimatch-10.2.6.cases.json'),
};
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const hashes = {};
for (const [name, path] of Object.entries(files)) hashes[name] = sha256(await readFile(path));
const provenance = JSON.parse(await readFile(join(root, 'verification/minimatch-10.2.6-source-only-20261016.json'), 'utf8'));
for (const row of provenance.sourceFiles) {
  const name = row.name === 'packageManager' ? 'caller' : row.name;
  if (hashes[name] !== row.sha256) throw Error(`source identity drift: ${name}`);
}
if (hashes.minimatch !== '59821ec2ce0d3df968292036e5c831ad322b33e9c33a949ecbc9dfe125d165be') throw Error('minimatch source drift');
const packageInfo = JSON.parse(await readFile(join(runtime, 'node_modules/minimatch/package.json'), 'utf8'));
if (packageInfo.version !== '10.2.6') throw Error('minimatch pin drift');
const { minimatch } = await import(pathToFileURL(files.minimatch).href);
const cases = JSON.parse(await readFile(files.cases, 'utf8'));
const rows = cases.map(row => ({ id: row.id, result: minimatch(row.path, row.pattern, row.options) }));
const evidence = {
  kind: 'original-dependency-control',
  sourceHead: '4dd2b149d155d7369de16ea4dc77c84e9f5ffb24',
  minimatchVersion: packageInfo.version,
  node: process.version,
  platform: process.platform,
  hashes,
  rows,
};
await writeFile(resolve(output), JSON.stringify(evidence, null, 2) + '\n', { flag: 'wx' });

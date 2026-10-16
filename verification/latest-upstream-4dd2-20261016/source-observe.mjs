import { registerHooks } from 'node:module';
import { readFileSync, realpathSync, existsSync, appendFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { resolve, join, sep } from 'node:path';
import { createHash } from 'node:crypto';
import { threadId } from 'node:worker_threads';

const evidence = 'C:/Users/adyba/pi-zig-latest-4dd2-models-20261016/verification/latest-upstream-4dd2-20261016/';
const records = 'C:/Users/adyba/pi-zig-update-evidence-20261003/latest-upstream-4dd2b149-audit-20261016/';
const root = realpathSync('C:/Users/adyba/pi-upstream-source-4dd2b149-20261016');
const old = realpathSync('C:/Users/adyba/pi-upstream-runtime-19cb534-20261012');
const evidenceRoot = realpathSync(evidence);
const audit = JSON.parse(readFileSync(join(evidence, 'dependency-contract-inherited4954.json')));
if (audit.latestHead !== '4dd2b149d155d7369de16ea4dc77c84e9f5ffb24' || audit.workspaces.length !== 16) throw Error('New immutable4dd2 workspace authority mismatch');
const frozen = new Map();
for (const manifest of ['source4dd-full-manifest-before.json', '../ai-model-operations-4954-20261015/reference-controls/source4954-runtime-manifest-20261015.json']) {
  for (const row of JSON.parse(readFileSync(join(evidence, manifest)))) frozen.set(realpathSync(row.path), row.sha256.toLowerCase());
}
if (!process.env.PI_SOURCE_ORACLE_CONTROL_MANIFEST) throw Error('Exact latest4dd control manifest is required');
for (const row of JSON.parse(readFileSync(process.env.PI_SOURCE_ORACLE_CONTROL_MANIFEST))) frozen.set(realpathSync(row.path), row.sha256.toLowerCase());
const seen = new Set();
const requiredByKind={
  summary30:['packages/coding-agent/src/core/compaction/compaction.ts','packages/coding-agent/src/core/compaction/branch-summarization.ts','packages/coding-agent/src/core/compaction/utils.ts','packages/coding-agent/src/core/model-resolver.ts'],
  summary45:['packages/coding-agent/src/core/compaction/compaction.ts','packages/coding-agent/src/core/compaction/utils.ts'],
  openai52:['packages/ai/src/api/openai-completions.ts','packages/ai/src/api/openai-responses-shared.ts'],
  google:['packages/ai/src/api/google-shared.ts'],
};
const captureKind=process.env.PI_LATEST_CAPTURE_KIND;
if(!Object.hasOwn(requiredByKind,captureKind))throw Error('Exact latest4dd capture kind is required');
function record(row) {
  appendFileSync(join(records, `source4dd2-modules-${process.pid}-${threadId}-20261016.jsonl`), JSON.stringify(row) + '\n');
}
function select(value) {
  if (typeof value === 'string') return value;
  if (!value || typeof value !== 'object') throw new Error('Unsupported official export');
  for (const key of ['source', 'import', 'default']) if (key in value) return select(value[key]);
  throw new Error('No executable official export');
}
function workspace(specifier) {
  for (const workspace of audit.workspaces) {
    if (specifier !== workspace.specifier && !specifier.startsWith(workspace.specifier + '/')) continue;
    const subpath = specifier === workspace.specifier ? '.' : './' + specifier.slice(workspace.specifier.length + 1);
    const pkg = JSON.parse(readFileSync(join(root, workspace.path, 'package.json')));
    const exports = pkg.exports;
    let target;
    if (typeof exports === 'string' || exports && !Object.keys(exports).some(key => key.startsWith('.'))) target = select(exports);
    else if (exports && exports[subpath]) target = select(exports[subpath]);
    else if (exports) {
      for (const [key, value] of Object.entries(exports)) {
        const star = key.indexOf('*');
        if (star < 0 || !subpath.startsWith(key.slice(0, star)) || !subpath.endsWith(key.slice(star + 1))) continue;
        target = select(value).replaceAll('*', subpath.slice(star, subpath.length - key.slice(star + 1).length));
        break;
      }
    } else if (subpath === '.') target = pkg.main;
    if (!target) throw new Error('Official package export absent ' + specifier);
    const officialTarget = target;
    if (target.startsWith('dist/')) target = './' + target;
    if (target.startsWith('./dist/')) target = target.replace('./dist/', './src/').replace(/\.js$/, '.ts').replace(/\.mjs$/, '.mts');
    const path = resolve(root, workspace.path, target);
    if (!path.startsWith(root + sep) || !existsSync(path)) throw new Error('Original Source target absent ' + specifier + ' -> ' + path);
    record({ kind: 'official-workspace-export-map', specifier, packageName: pkg.name, packageVersion: pkg.version, officialTarget, sourceTarget: target, path });
    return { url: pathToFileURL(path).href, shortCircuit: true };
  }
  return null;
}
function observe(url) {
  if (!url.startsWith('file:')) return;
  const path = realpathSync(fileURLToPath(url));
  if (path.startsWith(old + sep) && !path.includes(sep + 'node_modules' + sep)) throw new Error('Old Source class escaped latest reference ' + path);
  const externalControl = path.startsWith(evidenceRoot + sep);
  if (!frozen.has(path)) throw new Error('Unmanifested Source dependency or caller control ' + path);
  if (seen.has(path)) return;
  const sha256 = createHash('sha256').update(readFileSync(path)).digest('hex');
  if (frozen.has(path) && frozen.get(path) !== sha256) throw new Error('Observed module changed since full freeze ' + path);
  seen.add(path);
  record({ kind: 'observed-module', path, sha256, externalControl });
}
registerHooks({ resolve(specifier, context, next) {
  const result = workspace(specifier) ?? next(specifier, context);
  observe(result.url);
  return result;
} });
observe(import.meta.url);
process.once('beforeExit',()=>{
  const required=requiredByKind[captureKind].map(path=>realpathSync(join(root,path)));
  for(const path of required)if(!seen.has(path))throw Error('Actual latest Source closure was not observed '+path);
  writeFileSync(join(records,`source4dd2-closure-${process.pid}-${threadId}-20261016.json`),JSON.stringify({sourceHead:audit.latestHead,captureKind,pid:process.pid,threadId,required,observedFiles:seen.size,allObservedFilesFrozen:true,oldRuntimeSourceFallback:false},null,2));
});

// Verification only. Observe unchanged Node module loads against frozen files.
import { registerHooks } from 'node:module';
import { readFileSync, writeFileSync, realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
const hash = data => createHash('sha256').update(data).digest('hex').toUpperCase();
const manifestPath = process.env.PI_SDK_SOURCE_551_MANIFEST;
const outputPath = process.env.PI_SDK_SOURCE_551_CLOSURE;
if (!manifestPath || !outputPath) throw Error('Missing frozen Source551 observer paths');
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
const key = path => process.platform === 'win32' ? path.toLowerCase() : path;
const pinned = new Map(manifest.map(row => [key(row.path), row.sha256]));
manifest.length = 0;
const loaded = new Map();
const builtins = new Set();
registerHooks({
  load(url, context, nextLoad) {
    if (url.startsWith('node:')) {
      builtins.add(url);
      return nextLoad(url, context);
    }
    if (!url.startsWith('file:')) throw Error('Unpinned module URL: ' + url);
    const path = realpathSync.native(fileURLToPath(url));
    const pin = pinned.get(key(path));
    if (!pin) throw Error('Executed module is outside pre-frozen Source files: ' + path);
    const before = hash(readFileSync(path));
    if (before !== pin) throw Error('Executed module prehash drift: ' + path);
    const result = nextLoad(url, context);
    const after = hash(readFileSync(path));
    if (after !== before) throw Error('Executed module changed during load: ' + path);
    const source = result.source;
    loaded.set(key(path), {
      url, path, format: result.format, file_sha256: before,
      actual_loader_source_sha256: source == null ? null : hash(source),
      default_loader_returned_no_source: source == null,
    });
    return result;
  },
});
process.on('exit', code => {
  const records = [...loaded.values()].sort((a, b) => a.path.localeCompare(b.path));
  const drift = records.filter(row => hash(readFileSync(row.path)) !== row.file_sha256);
  writeFileSync(outputPath, JSON.stringify({
    schema: 'sdk-source551-executed-module-closure-v1', exit_code: code,
    manifest_sha256: hash(readFileSync(manifestPath)),
    observer_sha256: hash(readFileSync(fileURLToPath(import.meta.url))),
    node: { version: process.versions.node, executable: process.execPath, sha256: hash(readFileSync(process.execPath)) },
    unchanged_default_loader: true, loaded_count: records.length,
    builtin_modules: [...builtins].sort(), records, post_drift: drift,
  }, null, 2) + '\n');
});

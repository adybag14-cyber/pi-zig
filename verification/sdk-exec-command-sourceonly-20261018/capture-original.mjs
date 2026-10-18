// PREPARED ONLY. A separate Root-owned serial grant/fence/full original runtime
// seals and exact descendant ownership are required before invoking this file.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { dirname } from 'node:path';
const authority = JSON.parse(readFileSync(new URL('./authority.json', import.meta.url), 'utf8'));
for (const entry of authority.selected_original_files) {
  const file = authority.runtime_root + '/' + entry.relative_path;
  const hash = createHash('sha256').update(readFileSync(file)).digest('hex').toUpperCase();
  if (hash !== entry.sha256) throw new Error('Original exec dependency drift: ' + entry.relative_path);
}
const { execCommand } = await import(pathToFileURL(authority.runtime_root + '/packages/coding-agent/dist/core/exec.js').href);
const observe = (0, eval)(readFileSync(new URL('./caller.mjs', import.meta.url), 'utf8'));
const child = fileURLToPath(new URL('./child.cjs', import.meta.url));
const rows = await observe(execCommand, { executable: process.execPath, child, cwd: dirname(child), missing: 'pi-zig-owned-intentionally-missing-exec-20261018' });
process.stdout.write(JSON.stringify({ schema: 'actual-core-exec-original-v1', rows }) + '\n');

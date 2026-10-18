// Prepared ONLY. Root must provide the complete original-runtime owner/seals,
// sanitized environment, stdin fence and explicit serial capture grant.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import nodeURL from 'node:url';
import { fileURLToPath } from 'node:url';
const packet = fileURLToPath(new URL('.', import.meta.url));
const authority = JSON.parse(readFileSync(new URL('./authority.json', import.meta.url), 'utf8'));
for (const entry of authority.files) {
  if (!entry.original_relative_path) continue;
  const file = authority.runtime_root + '/' + entry.original_relative_path;
  const hash = createHash('sha256').update(readFileSync(file)).digest('hex').toUpperCase();
  if (hash !== entry.sha256) throw new Error('Original Git dependency byte mismatch: ' + entry.original_relative_path);
}
// Actual original published Pi code, with its actual original dependency graph.
const { parseGitUrl } = await import(pathToFileURL(authority.runtime_root + '/packages/coding-agent/dist/utils/git.js').href);
const cases = JSON.parse(readFileSync(packet + 'cases.json', 'utf8'));
const capture = (0, eval)(readFileSync(packet + 'caller.mjs', 'utf8'));
const rows = capture(parseGitUrl, nodeURL, cases);
process.stdout.write(JSON.stringify({ schema: 'actual-pi-git-url-original-v1', subject: 'original-published-pi-dist', rows }) + '\n');

import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const directory = process.env.PI_CATALOG_REPLAY_DIR;
if (!directory) throw new Error('PI_CATALOG_REPLAY_DIR required');
const responses = new Map();
for (const name of readdirSync(directory).filter(name => name.endsWith('.json'))) {
  const record = JSON.parse(readFileSync(join(directory, name), 'utf8'));
  const bytes = readFileSync(join(directory, record.body));
  if (createHash('sha256').update(bytes).digest('hex') !== record.sha256) throw new Error('Replay body digest mismatch');
  if (responses.has(record.url)) throw new Error('Duplicate replay URL');
  responses.set(record.url, { record, bytes });
}
const requested = new Set();
globalThis.fetch = async input => {
  const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
  const match = responses.get(url);
  if (!match || requested.has(url)) throw new Error(`Unexpected or repeated offline replay URL: ${url}`);
  requested.add(url);
  return new Response(match.bytes, { status: match.record.status, headers: match.record.headers });
};
process.on('beforeExit', () => {
  if (requested.size !== responses.size) throw new Error('Not all captured responses consumed');
});

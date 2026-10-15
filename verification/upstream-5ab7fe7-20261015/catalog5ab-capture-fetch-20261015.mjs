import { createHash } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const output = process.env.PI_CATALOG_CAPTURE_DIR;
if (!output) throw new Error('PI_CATALOG_CAPTURE_DIR required');
mkdirSync(output, { recursive: true });
const realFetch = globalThis.fetch;
let sequence = 0;
globalThis.fetch = async (input, options = {}) => {
  const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
  const id = String(++sequence).padStart(2, '0');
  const started = new Date().toISOString();
  const response = await realFetch(input, { ...options, signal: options.signal ?? AbortSignal.timeout(45000) });
  const bytes = Buffer.from(await response.clone().arrayBuffer());
  const sha256 = createHash('sha256').update(bytes).digest('hex');
  writeFileSync(join(output, `${id}-${sha256}.body`), bytes);
  writeFileSync(join(output, `${id}.json`), JSON.stringify({ url, started, completed: new Date().toISOString(), status: response.status, headers: Object.fromEntries(response.headers), body: `${id}-${sha256}.body`, bytes: bytes.length, sha256 }, null, 2) + '\n');
  return response;
};

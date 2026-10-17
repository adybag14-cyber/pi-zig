// Prepared original8efd probe. No expected observations are authored here.
// Requires the real accepted Source graph and its actual package dependencies.
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { readFileSync } from 'node:fs';
const root = process.env.PI_VERSION_SOURCE_ROOT;
const packageEntry = process.env.PI_VERSION_PACKAGE_URL;
if (!root || !packageEntry) throw Error('Actual accepted Source root and public SDK entry URL required');
const moduleUrl = relative => pathToFileURL(resolve(root, relative)).href;
const config = await import(moduleUrl('packages/coding-agent/src/config.ts'));
const sdk = await import(packageEntry);
const { getPiUserAgent } = await import(moduleUrl('packages/coding-agent/src/utils/pi-user-agent.ts'));
const { getLatestPiRelease, checkForNewPiVersion } = await import(moduleUrl('packages/coding-agent/src/utils/version-check.ts'));
const manifests = ['coding-agent', 'ai', 'agent', 'tui'].map(name => {
  const pkg = JSON.parse(readFileSync(resolve(root, `packages/${name}/package.json`), 'utf8'));
  return { name: pkg.name, version: pkg.version };
});
const originalFetch = globalThis.fetch;
const saved = new Map(['PI_OFFLINE', 'PI_SKIP_VERSION_CHECK'].map(name => [name, process.env[name]]));
const rows = [];
let calls = 0;
const marker = Object.freeze({ sourceProbeFetchBoundary: true });
// A transparent throwing boundary, never a successful response/factory stand-in.
// This observes whether the real Source version helper reaches fetch at all.
globalThis.fetch = async () => { calls++; throw marker; };
try {
  for (const flag of ['PI_OFFLINE', 'PI_SKIP_VERSION_CHECK']) {
    for (const value of [undefined, '', '0', 'false', ' ', '1']) {
      delete process.env.PI_OFFLINE;
      delete process.env.PI_SKIP_VERSION_CHECK;
      if (value !== undefined) process.env[flag] = value;
      const before = calls;
      let result, reason;
      try { result = flag === 'PI_OFFLINE' ? await getLatestPiRelease(config.VERSION) : await checkForNewPiVersion(config.VERSION); }
      catch (error) { reason = error; }
      rows.push({ flag, value: value === undefined ? null : value, fetchCalls: calls - before, returnedUndefined: result === undefined, exactMarker: reason === marker });
    }
  }
} finally {
  globalThis.fetch = originalFetch;
  for (const [name, value] of saved) { if (value === undefined) delete process.env[name]; else process.env[name] = value; }
}
console.log(JSON.stringify({ sourceCommit: '8efd314fa3d3232ce197d8d7a6a5660530b9d83e', manifests, configurationVersion: config.VERSION, publicSdkVersion: sdk.VERSION, userAgent: getPiUserAgent(config.VERSION), rows }));

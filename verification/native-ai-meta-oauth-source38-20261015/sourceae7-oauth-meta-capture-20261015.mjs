import { readFileSync, writeFileSync } from 'node:fs';
import { metaOAuth } from 'file:///C:/Users/adyba/pi-upstream-source-ae7b16d-20261015/packages/ai/src/auth/oauth/meta.ts';
globalThis.metaOAuth = metaOAuth;
const inputPath = 'C:/Users/adyba/pi-zig-native-meta-oauth-20261015/src/extensions/fixtures/ai-oauth-meta-ae7.input.txt';
const input = readFileSync(inputPath, 'utf8');
await (new Function('return (async()=>{' + input + '\n})()'))();
writeFileSync(process.argv[2], JSON.stringify({ runtime: process.version, count: globalThis.metaOAuthRows.length, clock: 'controlled Date.now and microtask sleep only; owner deadline uses wall clock', sourceHead: 'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d', rows: globalThis.metaOAuthRows }, null, 2) + '\n');
console.log(JSON.stringify({ rows: globalThis.metaOAuthRows.length, network: 'controlled fake fetch only' }));



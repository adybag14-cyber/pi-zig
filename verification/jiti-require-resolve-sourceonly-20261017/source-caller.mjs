// PREPARED ONLY. The future controller supplies the exact official jiti2.7
// factory, its actual bundled Babel transform and a new owned fixture dir.
// No dependency discovery, network, npm, deleted runtime or substitute subject.
import { createRequire } from 'node:module';
import { writeFileSync, mkdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import * as fs from 'node:fs';

const nativeRequire = createRequire(import.meta.url);
const createJiti = nativeRequire(process.argv[2]);
const transform = nativeRequire(process.argv[3]);
const root = resolve(process.argv[4]);
// The controller must establish this new owned dir before admission. This
// caller writes only original fixture bytes beneath it and does no cleanup.
const files = {
  'entry.cjs': 'module.exports = undefined;',
  'value.cjs': 'module.exports={answer:42};',
  'self.json': '{"answer":42}',
  'false.json': 'false',
  'true.json': 'true',
  'null.json': 'null',
  'existing-default.json': '{"default":"original","answer":42}',
  'space name.cjs': 'module.exports={encoded:true};',
  'value.ts': 'export const answer:number=42;',
  'index-dir/index.ts': 'export const directory=true;',
  'cycle-a.ts': "import { seen } from './cycle-b.ts'; export function early(){return 'early'} export const ready='ready'; export const result=seen;",
  'cycle-b.ts': "import { early,ready } from './cycle-a.ts'; export const seen=[early(),ready];",
  'raw.cjs': 'throw globalThis.ownedJitiReason;',
  'counter.cjs': 'globalThis.ownedJitiLoads++;module.exports={load:globalThis.ownedJitiLoads};',
  'node_modules/conditional/package.json': '{"name":"conditional","exports":{".":{"owned":"./owned.cjs","import":"./import.cjs","require":"./require.cjs"},"./hidden":null}}',
  'node_modules/conditional/owned.cjs': 'module.exports={condition:"owned"};',
  'node_modules/conditional/import.cjs': 'module.exports={condition:"import"};',
  'node_modules/conditional/require.cjs': 'module.exports={condition:"require"};',
};
for (const [relative, bytes] of Object.entries(files)) {
  const filename = join(root, relative);
  mkdirSync(join(filename, '..'), { recursive: true });
  writeFileSync(filename, bytes, 'utf8');
}
const options = { fsCache: false, interopDefault: false, transform };
const parent = { createRequire, onError(error) { throw error; }, nativeImport(id) { return import(id); } };
const make = extra => createJiti(join(root, 'entry.cjs'), { ...options, ...extra }, parent);
const rows = [];
async function row(id, run) {
  try { rows.push({ id, status: 'returned', value: await run() }); }
  catch (error) { rows.push({ id, status: 'thrown', type: typeof error, name: error?.name, message: error?.message, code: error?.code, sameOwnedReason: error === globalThis.ownedJitiReason }); }
}
const jiti = make();
await row('node-protocol-builtin', () => ({ same: jiti('node:fs') === nativeRequire('node:fs') }));
await row('bare-builtin', () => ({ same: jiti('fs') === nativeRequire('fs') }));
await row('encoded-file-url', () => jiti(pathToFileURL(join(root, 'space name.cjs')).href));
await row('json-self-default', () => { const value = jiti('./self.json'); const descriptor=Object.getOwnPropertyDescriptor(value,'default'); return { self: value.default === value, descriptor: { selfValue:descriptor.value===value, writable:descriptor.writable, enumerable:descriptor.enumerable, configurable:descriptor.configurable }, keys: Object.keys(value), answer: value.answer }; });
await row('json-existing-default', () => jiti('./existing-default.json'));
await row('json-falsy-primitive', () => jiti('./false.json'));
await row('json-null', () => jiti('./null.json'));
await row('json-truthy-primitive-in-error', () => jiti('./true.json'));
await row('data-sync-error', () => jiti('data:text/javascript,export default 42'));
await row('data-async-native', () => jiti.import('data:text/javascript,export const answer=42'));
await row('typescript-extension-search', () => jiti('./value'));
await row('typescript-index-search', () => jiti('./index-dir'));
await row('javascript-to-typescript-substitution', () => jiti('./value.js'));
await row('actual-conditional-require', () => jiti('conditional'));
await row('actual-conditional-import', () => jiti.import('conditional'));
await row('actual-explicit-condition', () => jiti.esmResolve('conditional', { conditions: ['owned'] }));
await row('package-hidden-subpath', () => jiti.resolve('conditional/hidden'));
await row('try-missing-is-undefined', () => ({ missing: jiti.esmResolve('./never-created', { try: true }) === undefined }));
await row('alias-segment-and-order', () => make({ alias: { '@owned': root, '@owned/value': join(root, 'value.cjs') } })('@owned/value'));
await row('virtual-module-exact-identity', () => { const module = { answer: 42 }; const instance = make({ virtualModules: { owned: module } }); return { same: instance('owned') === module }; });
await row('virtual-inherited-module', () => make({ virtualModules: Object.create({ inherited: { answer: 42 } }) })('inherited'));
await row('builtin-precedes-virtual', () => ({ same: make({ virtualModules: { fs: { wrong: true } } })('fs') === fs.default }));
await row('cycle-sees-actual-partial-module', () => jiti('./cycle-a.ts'));
globalThis.ownedJitiReason = Object.freeze({ raw: 'owned unbranded failure' });
await row('raw-source-rejection-identity', () => jiti('./raw.cjs'));
globalThis.ownedJitiLoads = 0;
await row('module-cache-load-identity', () => { const instance = make(); const a=instance('./counter.cjs'),b=instance('./counter.cjs'); return { same:a===b, first:a.load, second:b.load }; });
await row('module-cache-false-native-retry', () => { const instance=make({moduleCache:false,tryNative:true}); const a=instance('./counter.cjs'),b=instance('./counter.cjs'); return { same:a===b, first:a.load, second:b.load }; });
await row('try-native-ts-fallback', () => make({ tryNative:true })('./value.ts'));
await row('resolve-paths-owned-search-root', () => jiti.resolve('conditional', { paths: [root] }));
await row('resolve-paths-public-identity', () => { const actual=createRequire(join(root,'entry.cjs')); return { same: jiti.resolve.paths === actual.resolve.paths, type:typeof jiti.resolve.paths }; });
process.stdout.write(JSON.stringify({ authority:'jiti2.7.0-original', rows })+'\n');

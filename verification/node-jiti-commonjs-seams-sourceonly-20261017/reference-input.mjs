// PREPARED ORIGINAL NODE24 CALLER ONLY. No expected data or native subject.
// Root must bind the pinned Node executable and a fresh owned contained root.
import Module, { builtinModules, createRequire, isBuiltin } from 'node:module';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const root = resolve(process.argv[2]);
process.chdir(root); // Dedicated child's controlled working directory only.
// All observable lookup lists use controlled child-only environment values.
// Keep prior values solely for restoration; never serialize or interpolate them.
const controlledKeys = ['HOME', 'USERPROFILE', 'NODE_PATH'];
const saved = new Map(controlledKeys.map(key => [key, { own: Object.hasOwn(process.env, key), value: process.env[key] }]));
process.env.HOME = join(root, 'controlled-home');
process.env.USERPROFILE = join(root, 'controlled-home');
delete process.env.NODE_PATH;
Module._initPaths();
const rows = [];
const reason = Object.freeze({ originalControlledReason: true });
function row(id, run) {
  const events = [];
  try { rows.push({ id, status: 'returned', value: run(events), events }); }
  catch (error) { rows.push({ id, status: 'thrown', type: typeof error, name: error?.name,
    code: error?.code, message: error?.message, sameReason: error === reason, events }); }
}
function put(relative, content) {
  const filename = join(root, relative);
  mkdirSync(join(filename, '..'), { recursive: true });
  writeFileSync(filename, content, { encoding: 'utf8', flag: 'wx' });
}
for (const [file, content] of Object.entries({
  'entry.cjs': 'module.exports = {};',
  'sub/entry.cjs': 'module.exports = {};',
  'relative.cjs': 'module.exports = { marker: "relative" };',
  'extra/relative.cjs': 'module.exports = { marker: "extra-relative" };',
  'node_modules/owned/package.json': '{"name":"owned","main":"entry.cjs"}',
  'node_modules/owned/entry.cjs': 'module.exports = { marker: "ordinary" };',
  'extra/node_modules/owned/package.json': '{"name":"owned","main":"entry.cjs"}',
  'extra/node_modules/owned/entry.cjs': 'module.exports = { marker: "extra" };',
  'node_modules/conditional/package.json': '{"name":"conditional","exports":{".":{"require":"./require.cjs","import":"./import.mjs"},"./hidden":null}}',
  'node_modules/conditional/require.cjs': 'module.exports = {};',
  'node_modules/conditional/import.mjs': 'export default {};',
  'suffix.custom.js': 'module.exports = {};',
  'custom.owned': 'owned native caller bytes',
  'data.json': '{"marker":"json"}',
})) put(file, content);
const parent = join(root, 'entry.cjs');
const require = createRequire(parent);
const second = createRequire(join(root, 'sub', 'entry.cjs'));
const functionShape = fn => ({ name: fn.name, length: fn.length,
  ownsPrototype: Object.hasOwn(fn, 'prototype'),
  prototypeConstructor: Object.hasOwn(fn, 'prototype') && fn.prototype.constructor === fn });
const descriptor = (object, key) => {
  const d = Object.getOwnPropertyDescriptor(object, key);
  return d && { enumerable: d.enumerable, configurable: d.configurable,
    writable: d.writable, hasGet: typeof d.get === 'function', hasSet: typeof d.set === 'function' };
};
const originalBuiltinList = [...builtinModules];
const initial = {
  nodeVersion: process.version, execPath: process.execPath,
  builtinModules: originalBuiltinList, builtinFrozen: Object.isFrozen(builtinModules),
  builtinSameDefaultExport: builtinModules === Module.builtinModules,
  builtinProperty: descriptor(Module, 'builtinModules'),
  builtinChecks: originalBuiltinList.map(id => ({ id, bare: isBuiltin(id), prefixed: isBuiltin(`node:${id}`) })),
  extraBuiltinChecks: ['test', 'node:test', 'sqlite', 'node:sqlite', 'sea', 'node:sea', 'not-an-owned-builtin', 'node:not-an-owned-builtin'].map(id => ({ id, builtin: isBuiltin(id) })),
  extensions: Object.keys(require.extensions), extensionNullPrototype: Object.getPrototypeOf(require.extensions) === null,
  extensionsSameModule: require.extensions === Module._extensions,
  extensionsShared: require.extensions === second.extensions,
  extensionFunctions: Object.keys(require.extensions).map(key => ({ key, ...functionShape(require.extensions[key]), descriptor: descriptor(require.extensions, key) })),
  requireShape: functionShape(require), resolveShape: functionShape(require.resolve), pathsShape: functionShape(require.resolve.paths),
  isBuiltinShape: functionShape(isBuiltin),
  modulePrivateShapes: ['_resolveLookupPaths', '_resolveFilename', '_findPath', '_nodeModulePaths', '_initPaths'].map(key => ({ key, ...functionShape(Module[key]) })),
  requireDescriptors: ['cache', 'extensions', 'main', 'resolve'].map(key => ({ key, ...descriptor(require, key) })),
  cacheShared: require.cache === second.cache && require.cache === Module._cache,
  resolveShared: require.resolve === second.resolve, pathsShared: require.resolve.paths === second.resolve.paths,
  mainSame: require.main === process.mainModule,
};
row('resolve-default-omitted', () => require.resolve('owned'));
row('resolve-default-undefined', () => require.resolve('owned', undefined));
row('resolve-default-null', () => require.resolve('owned', null));
row('resolve-default-nonobject', () => require.resolve('owned', 1));
row('resolve-paths-undefined', events => require.resolve('owned', { get paths() { events.push('paths'); return undefined; } }));
row('resolve-options-conditions-before-paths', events => require.resolve('owned', {
  get conditions() { events.push('conditions'); return undefined; },
  get paths() { events.push('paths'); return undefined; },
}));
row('builtin-before-options-getter', () => require.resolve('node:fs', { get paths() { throw reason; }, get conditions() { throw reason; } }));
row('bare-builtin-before-options-getter', () => require.resolve('fs', { get paths() { throw reason; }, get conditions() { throw reason; } }));
row('paths-extra-root', () => require.resolve('owned', { paths: [join(root, 'extra')] }));
row('paths-relative-root', () => require.resolve('./relative.cjs', { paths: [join(root, 'extra')] }));
row('paths-empty-missing', () => require.resolve('owned', { paths: [] }));
row('paths-empty-absolute', () => require.resolve(join(root, 'relative.cjs'), { paths: [] }));
for (const value of [null, false, 'controlled', {}, [null], [1], ['']])
  row(`paths-invalid-${JSON.stringify(value)}`, () => require.resolve('owned', { paths: value }));
row('paths-getter-identity', () => require.resolve('owned', { get paths() { throw reason; } }));
row('conditions-getter-identity', () => require.resolve('owned', { get conditions() { throw reason; } }));
row('paths-array-live-index-order', events => {
  const paths = new Proxy([join(root, 'extra'), root], { get(target, key, receiver) {
    if (key === 'length' || key === '0' || key === '1') events.push(`array:${String(key)}`);
    return Reflect.get(target, key, receiver);
  } });
  return require.resolve('owned', { get paths() { events.push('options.paths'); return paths; } });
});
row('paths-ignored-iterator', () => require.resolve('owned', { paths: {
  *[Symbol.iterator]() { yield root; },
} }));
row('paths-method-builtins', () => ['fs', 'node:fs', 'node:test', 'node:not-an-owned-builtin'].map(id => ({ id, paths: require.resolve.paths(id) })));
row('paths-method-relative-absolute-bare', () => ['./relative.cjs', '../relative.cjs', '..', '.', '.unusual', join(root, 'relative.cjs'), 'owned'].map(id => ({ id, paths: require.resolve.paths(id) })));
for (const value of [undefined, null, 1, {}, Symbol('controlled')])
  row(`paths-method-type-${typeof value}`, () => require.resolve.paths(value));
row('require-extra-argument-ignored', () => require('./data.json', { get paths() { throw reason; } }));
row('resolve-custom-extension-suffix', () => require.resolve('./suffix.custom'));
row('resolve-hidden-package-subpath', () => require.resolve('conditional/hidden'));
row('extensions-real-dispatch', () => {
  require.extensions['.owned'] = function controlledOwnedHandler(module, filename) {
    module.exports = { filename, parentIdentity: module instanceof Module, marker: 'real-handler' };
  };
  try { return require('./custom.owned'); }
  finally { delete require.extensions['.owned']; }
});

// Change only this dedicated Node child's environment. Never print prior values.
try {
  for (const [id, nodePath] of [['no-node-path', undefined], ['controlled-node-path', join(root, 'controlled-global-a') + ';' + join(root, 'controlled-global-b')]]) {
    process.env.HOME = join(root, 'controlled-home');
    process.env.USERPROFILE = join(root, 'controlled-home');
    if (nodePath === undefined) delete process.env.NODE_PATH;
    else process.env.NODE_PATH = process.platform === 'win32' ? nodePath : nodePath.replaceAll(';', ':');
    Module._initPaths();
    row(`initPaths-${id}`, () => {
      const value = { globalPaths: [...Module.globalPaths], bareLookup: require.resolve.paths('owned'), relativeLookup: require.resolve.paths('./relative.cjs') };
      Module.globalPaths.push(join(root, 'controlled-public-only'));
      value.afterPublicCloneMutation = require.resolve.paths('owned');
      return value;
    });
  }
} finally {
  for (const key of controlledKeys) {
    const entry = saved.get(key);
    if (entry.own) process.env[key] = entry.value;
    else delete process.env[key];
  }
  Module._initPaths();
}
process.stdout.write(JSON.stringify({ authority: 'original-Node24.14.0-CommonJS', originalBuiltinList, initial, rows }) + '\n');

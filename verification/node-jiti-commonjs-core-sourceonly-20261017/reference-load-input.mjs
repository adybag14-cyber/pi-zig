// Genuine original Node24 public loader inputs. Expected/observed absent.
import fs from 'node:fs';
import path from 'node:path';
import Module from 'node:module';
if (process.version !== 'v24.14.0') throw new Error('exact original Node24.14.0 required');
const root = path.resolve(process.argv[2]);
if (!path.isAbsolute(process.argv[2]) || fs.existsSync(root)) throw new Error('fresh absolute owned fixture root required');
fs.mkdirSync(root, { recursive: false });
for (const [file, source] of Object.entries({
  'normal.cjs': 'module.exports={actual:41};',
  'cycle-a.cjs': 'exports.name="a";exports.other=require("./cycle-b.cjs").name;',
  'cycle-b.cjs': 'exports.name="b";exports.other=require("./cycle-a.cjs").name;',
  'ordinary.owned': 'owned-handler',
  'cleanup.owned': 'owned-handler',
  'custom.owned': 'owned-handler',
})) fs.writeFileSync(path.join(root, file), source);
const parent = new Module(path.join(root, 'parent.cjs')); parent.filename = parent.id;
const require = Module.createRequire(parent.filename);
const reason = Object.freeze({ owned: 'load-reason' });
const cleanupReason = Object.freeze({ owned: 'cleanup-reason' });
const rows = [];
function observe(id, operation) {
  try { rows.push({ id, status: 'returned', value: operation() }); }
  catch (error) { rows.push({ id, status: 'thrown', type: typeof error, name: error?.name, code: error?.code, message: error?.message, sameReason: error === reason, sameCleanupReason: error === cleanupReason }); }
}
observe('load-ordinary-shape', () => ({ name: Module._load.name, length: Module._load.length, ownsPrototype: Object.hasOwn(Module._load, 'prototype') }));
observe('load-real-module-cache-first-parent-and-children', () => {
  const filename = path.join(root, 'normal.cjs');
  const first = Module._load(filename, parent, false);
  const other = new Module(path.join(root, 'other.cjs'));
  const second = Module._load(filename, other, false);
  return { same: first === second, realInstance: Module._cache[filename] instanceof Module, firstParent: Module._cache[filename].parent === parent, parentChildren: parent.children.filter(m => m.filename === filename).length, otherChildren: other.children.filter(m => m.filename === filename).length };
});
observe('load-relative-cache-retains-live-exports', () => {
  const filename = path.join(root, 'normal.cjs'); const replacement = { replacement: 43 };
  Module._cache[filename].exports = replacement;
  return { same: Module._load('./normal.cjs', parent, false) === replacement, required: require('./normal.cjs') === replacement };
});
observe('load-real-circular-modules', () => ({ value: Module._load(path.join(root, 'cycle-a.cjs'), parent, false), loaded: Module._cache[path.join(root, 'cycle-a.cjs')].loaded }));
const originalOwned = Module._extensions['.owned'];
try {
  Module._extensions['.owned'] = function (mod, filename) {
    if (path.basename(filename) !== 'custom.owned') throw reason;
    mod.exports = { actual: 47, parent: mod.parent === parent, filename };
  };
  observe('load-genuine-custom-extension', () => Module._load(path.join(root, 'custom.owned'), parent, false));
  observe('load-ordinary-failure-removes-cache-and-child', () => {
    const filename = path.join(root, 'ordinary.owned');
    try { Module._load(filename, parent, false); }
    catch (error) { return { sameReason: error === reason, cached: Object.hasOwn(Module._cache, filename), retainedChild: parent.children.some(m => m.filename === filename) }; }
  });
  observe('load-finally-cleanup-error-replaces-ordinary-load-error', () => {
    const cleanupParent = new Module(path.join(root, 'cleanup-parent.cjs'));
    cleanupParent.children = new Proxy([], { deleteProperty() { throw cleanupReason; } });
    return Module._load(path.join(root, 'cleanup.owned'), cleanupParent, false);
  });
} finally {
  if (originalOwned === undefined) delete Module._extensions['.owned']; else Module._extensions['.owned'] = originalOwned;
}
observe('load-node-prefix-before-cache-bare-after-cache', () => {
  const previous = Module._cache.fs; const sentinel = { userCache: true };
  try {
    Module._cache.fs = { loaded: true, exports: sentinel };
    return { bare: Module._load('fs', parent, false) === sentinel, prefixed: Module._load('node:fs', parent, false) === fs };
  } finally { if (previous === undefined) delete Module._cache.fs; else Module._cache.fs = previous; }
});
process.stdout.write(JSON.stringify({ authority: { nodeVersion: process.version, execPath: process.execPath }, rows }) + '\n');

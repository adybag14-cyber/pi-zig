// Prepared shared original/native control. The owner supplies an EMPTY retained
// physical fixture root and the actual mkdir binding; this file deletes nothing.
import fs from 'node:fs';
import path from 'node:path';
import { Buffer } from 'node:buffer';
import { pathToFileURL } from 'node:url';
const mkdir = globalThis.mkdirFixtureBinding;
const root = globalThis.mkdirFixtureRoot;
function check(condition, detail) { if (!condition) throw Error(detail); }
check(typeof mkdir === 'function' && typeof root === 'string', 'actual fixture inputs required');
check(mkdir.name === 'mkdir' && mkdir.length === 2, 'function metadata');
check(Object.getPrototypeOf(mkdir) === Object.getPrototypeOf(async function() {}), 'intrinsic async prototype');
check(!Object.hasOwn(mkdir, 'prototype'), 'async function owns no constructor prototype');
try { new mkdir(); throw Error('constructible mkdir'); } catch (e) { check(e instanceof TypeError, 'constructor rejection'); }
const rows = [];
const first = path.join(root, 'first');
const deep = path.join(first, 'second', 'third');
const order = [];
const pending = mkdir(deep, { recursive: true });
check(pending instanceof Promise, 'real Promise');
pending.then(() => order.push('completed'));
order.push('sync');
Promise.resolve().then(() => order.push('microtask'));
const created = await pending;
check(typeof created === 'string' && fs.statSync(created).isDirectory(), 'first result refers to actual directory');
const namespace = String.fromCharCode(92, 92, 63, 92);
const unc = namespace + 'UNC' + String.fromCharCode(92);
const comparable = created.startsWith(unc) ? String.fromCharCode(92, 92) + created.slice(8) : created.startsWith(namespace) ? created.slice(4) : created;
check(path.resolve(comparable) === path.resolve(first), 'first physical ancestor result');
check(fs.statSync(deep).isDirectory(), 'deep directory physically exists');
check(order.join(',') === 'sync,microtask,completed', 'owner microtask ordering');
rows.push(['recursive-created', created, order]);
check(await mkdir(deep, { recursive: true }) === undefined, 'existing recursive result');
const leaf = path.join(root, 'leaf');
check(await mkdir(leaf, '750') === undefined && fs.statSync(leaf).isDirectory(), 'nonrecursive mode shortcut');
for (const [target, options, code] of [
  [leaf, undefined, 'EEXIST'],
  [path.join(root, 'missing-parent', 'child'), undefined, 'ENOENT'],
  ['', undefined, 'ENOENT'],
]) {
  try { await mkdir(target, options); throw Error('filesystem failure accepted'); }
  catch (e) {
    check(e instanceof Error && e.code === code && e.syscall === 'mkdir' && typeof e.errno === 'number', 'filesystem error fields');
    check(typeof e.path === 'string', 'filesystem error path');
    rows.push(['error', e.code, e.syscall, e.path]);
  }
}
const file = path.join(root, 'ordinary-file');
fs.writeFileSync(file, 'retained');
try { await mkdir(file, { recursive: true }); throw Error('file accepted'); }
catch (e) { check(e.code === 'EEXIST', 'recursive ordinary file error'); }
const original = {};
const getters = [];
const invalid = mkdir(null, {
  get recursive() { getters.push('recursive'); return false; },
  get mode() { getters.push('mode'); throw original; },
});
check(invalid instanceof Promise, 'validation returns rejected Promise');
try { await invalid; throw Error('getter accepted'); } catch (e) { check(e === original, 'getter identity'); }
check(getters.join(',') === 'recursive,mode', 'options before path validation');
const ignoresSignal = path.join(root, 'ignored-signal');
check(await mkdir(ignoresSignal, { get signal() { throw original; } }) === undefined, 'Source mkdir ignores signal option');
const bytePath = path.join(root, 'bytes');
check(await mkdir(Buffer.from(bytePath)) === undefined && fs.statSync(bytePath).isDirectory(), 'Buffer path');
const urlPath = path.join(root, 'url');
check(await mkdir(pathToFileURL(urlPath)) === undefined && fs.statSync(urlPath).isDirectory(), 'file URL path');
const mutated = Buffer.from(path.join(root, 'copied-buffer'));
const saved = Buffer.from(mutated).toString();
const copied = mkdir(mutated);
mutated.fill(0x78);
await copied;
check(fs.statSync(saved).isDirectory(), 'path copied before suspension');
for (const [options, code] of [
  [{ recursive: null }, 'ERR_INVALID_ARG_TYPE'],
  [{ mode: '888' }, 'ERR_INVALID_ARG_VALUE'],
  [{ mode: -1 }, 'ERR_OUT_OF_RANGE'],
  [{ mode: 1.5 }, 'ERR_OUT_OF_RANGE'],
  [{ mode: {} }, 'ERR_INVALID_ARG_TYPE'],
]) {
  let returned;
  try { returned = mkdir(path.join(root, 'must-not-create'), options); }
  catch (e) { throw Error('async validation threw synchronously'); }
  try { await returned; throw Error('invalid options accepted'); }
  catch (e) { check(e.code === code, 'validation error code'); }
}
check(!fs.existsSync(path.join(root, 'must-not-create')), 'invalid options have no filesystem effect');
export const observations = rows;

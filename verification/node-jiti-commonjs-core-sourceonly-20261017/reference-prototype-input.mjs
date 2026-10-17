// Original Node24 observer only. No candidate runtime or substitute namespace.
import fs from 'node:fs';
import path from 'node:path';
import Module from 'node:module';
const root = path.resolve(process.argv[2]);
if (!path.isAbsolute(process.argv[2]) || fs.existsSync(root)) throw new Error('fresh absolute owned fixture root required');
fs.mkdirSync(root, { recursive: false });
const rows = [];
const events = [];
function observe(id, operation) {
  events.length = 0;
  try { rows.push({ id, status: 'returned', value: operation(), events: [...events] }); }
  catch (reason) { rows.push({ id, status: 'thrown', type: typeof reason, name: reason?.name, code: reason?.code, message: reason?.message, sameReason: reason === marker, events: [...events] }); }
}
const marker = Object.freeze({ owned: 'raw-reason' });
const filename = path.join(root, 'owned.cjs');
fs.writeFileSync(filename, 'module.exports={real:true};');
function fresh() { const mod = new Module(filename); mod.filename = filename; return mod; }
const originalLoad = Module._load;
try {
  const promise = Promise.resolve('owned-raw-promise');
  Module._load = function (...args) { events.push({ thisModule: this === Module, args: [args[0], args[1] === parent, args[2]] }); return promise; };
  const parent = fresh();
  observe('prototype-require-raw-promise', () => ({ samePromise: Module.prototype.require.call(parent, 'owned') === promise }));
  observe('prototype-require-validates-before-load', () => Module.prototype.require.call(parent, 1));
  observe('prototype-require-empty-before-load', () => Module.prototype.require.call(parent, ''));
  Module._load = function () { events.push('load'); throw marker; };
  observe('prototype-require-raw-throw', () => Module.prototype.require.call(parent, 'owned'));
} finally { Module._load = originalLoad; }
const originalPaths = Module._nodeModulePaths;
const originalDirname = path.dirname;
const originalExtensions = Module._extensions;
try {
  Module._nodeModulePaths = function (directory) { events.push({ paths: directory, thisModule: this === Module }); return ['owned-paths']; };
  path.dirname = function (name) { events.push('dirname'); Module._nodeModulePaths = () => { throw marker; }; return originalDirname(name); };
  const registry = Object.create(null);
  registry['.multi.cjs'] = function (mod, name) { events.push({ handler: '.multi.cjs', receiver: this === registry, filename: name, module: mod === current }); mod.exports = { custom: true }; };
  registry['.cjs'] = function () { throw marker; };
  Module._extensions = registry;
  const current = { id: 'owned-borrowed', loaded: false, filename: null, paths: null, exports: undefined };
  observe('prototype-load-callee-capture-longest-extension', () => {
    Module.prototype.load.call(current, path.join(root, 'file.multi.cjs'));
    return { loaded: current.loaded, paths: current.paths, exports: current.exports };
  });
  const throwing = { id: 'owned-throw', loaded: false, filename, paths: [], exports: undefined };
  registry['.js'] = function () { throw marker; };
  observe('prototype-load-throw-does-not-mark-loaded', () => {
    try { Module.prototype.load.call(throwing, filename); }
    catch (reason) { return { sameReason: reason === marker, loaded: throwing.loaded }; }
  });
} finally { Module._nodeModulePaths = originalPaths; path.dirname = originalDirname; Module._extensions = originalExtensions; }
observe('prototype-compile-actual-wrapper-bindings', () => {
  const mod = fresh();
  mod.require = function (id) { return { id, receiver: this === mod }; };
  const result = mod._compile('exports.observed={sameThis:this===exports,sameModule:module.exports===exports,filename:__filename,dirname:__dirname,required:require("owned")};return 29;', filename, 'commonjs');
  return { result, exports: mod.exports, executing: Object.getOwnPropertySymbols(mod).filter(s => s.description === 'kIsExecuting').map(s => mod[s]) };
});
observe('prototype-compile-throw-keeps-executing', () => {
  const mod = fresh();
  try { mod._compile('throw 73;', filename, 'commonjs'); }
  catch (reason) { return { raw: reason, executing: Object.getOwnPropertySymbols(mod).filter(s => s.description === 'kIsExecuting').map(s => mod[s]) }; }
});
observe('prototype-load-real-json', () => {
  const json = path.join(root, 'owned.json'); fs.writeFileSync(json, '{"actual":31}');
  const mod = new Module(json); mod.load(json); return { exports: mod.exports, loaded: mod.loaded };
});
process.stdout.write(JSON.stringify({ authority: { nodeVersion: process.version, execPath: process.execPath }, rows }) + '\n');

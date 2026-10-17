// Genuine original Node24 internal compiler observer. Requires an explicitly
// admitted --expose-internals capture; no candidate or fake binding is imported.
import fs from 'node:fs';
import path from 'node:path';
import Module from 'node:module';
if (process.version !== 'v24.14.0') throw new Error('exact original Node24.14.0 required');
const require = Module.createRequire(import.meta.url);
const { internalBinding } = require('internal/test/binding');
const contextify = internalBinding('contextify');
const root = path.resolve(process.argv[2]);
if (!path.isAbsolute(process.argv[2]) || fs.existsSync(root)) throw new Error('fresh absolute owned fixture root required');
fs.mkdirSync(root, { recursive: false });
globalThis.ownedCompilerBody = 0;
globalThis.ownedCompileEscape = false;
globalThis.ownedCompilerReason = Object.freeze({ compiler: 'ordinary-reason' });
globalThis.ownedCompilerPromise = Promise.resolve(67);
const cases = [
  ['arbitrary-valid-cjs-body', 'class Box{#x=5;get(){return this.#x}};function* seq(){yield 3};const obj={...{a:2}};exports.value=new Box().get()+obj.a+[...seq()][0];exports.sameThis=this===exports;exports.sameModule=module.exports===exports;exports.filename=__filename;exports.dirname=__dirname;exports.requireType=typeof require;globalThis.ownedCompilerBody++;return 47;', true],
  ['top-level-return', 'return 53;', true],
  ['strict-cjs-this', '"use strict";exports.sameThis=this===exports;return arguments.length;', true],
  ['bom-body', '\uFEFFexports.value=59;', true],
  ['hashbang-body', '#!/usr/bin/env node\nexports.value=61;', true],
  ['keyword-string', 'exports.text="import export await import.meta";', true],
  ['keyword-comment', '// import x from "absent"; export default await 0;\nexports.value=1;', true],
  ['keyword-regex', 'exports.value=/sourceMappingURL=not-metadata/.test("sourceMappingURL=not-metadata");', true],
  ['nested-async-await', 'exports.run=async function(){await 0;return 1};', false],
  ['static-import-missing-dependency-parse-only', 'import "./never-created.mjs";', false],
  ['unreachable-import-meta', 'if(false)console.log(import.meta);', false],
  ['unreachable-top-level-await', 'if(false)await 0;', false],
  ['cjs-parameter-lexical-conflict', 'const module=1;globalThis.ownedCompilerBody++;', false],
  ['invalid-cjs-and-esm', 'const = ;', false],
  ['wrapper-escape-payload', '});globalThis.ownedCompileEscape=true;(function(){', false],
  ['source-url', 'exports.value=1;\n//# sourceURL=owned-source.js', false],
  ['source-map-url', 'exports.value=1;\n//# sourceMappingURL=owned.map', false],
  ['both-directives', 'exports.value=1;\n//# sourceURL=owned-both.js\n//# sourceMappingURL=owned-both.map', false],
  ['template-fake-directive', 'exports.text=`\n//# sourceURL=inside-template.js\n//# sourceMappingURL=inside-template.map\n`;', false],
  ['raw-promise-return', 'return globalThis.ownedCompilerPromise;', true],
  ['raw-thrown-object', 'throw globalThis.ownedCompilerReason;', true],
  ['direct-module-error-invalid-esm-tail', 'export const = ;', false],
  ['parse-required-conflict-invalid-esm-tail', 'const module=1;const = ;', false],
  ['detect-disabled-valid-esm-original-warning', 'export const actual=71;', false, false],
  ['detect-disabled-warning-listener-raw-throw', 'export const actual=73;', false, false, true],
];
const rows = [];
function errorRecord(error) { return { type: typeof error, name: error?.name, code: error?.code, message: error?.message, stack: error?.stack, sameReason: error === globalThis.ownedCompilerReason }; }
for (const [id, code, invoke, detect = true, throwWarning = false] of cases) {
  const filename = path.join(root, id + '.cjs');
  const before = globalThis.ownedCompilerBody;
  const warningListener = warning => { if (warning.message.startsWith('Failed to load the ES module: ')) throw globalThis.ownedCompilerReason; };
  if (throwWarning) process.on('warning', warningListener);
  try {
    const result = contextify.compileFunctionForCJSLoader(code, filename, false, detect);
    const fn = result.function;
    const row = { id, status: 'returned', keys: Object.keys(result), cachedDataRejected: result.cachedDataRejected, sourceURL: result.sourceURL, sourceMapURL: result.sourceMapURL, canParseAsESM: result.canParseAsESM, functionType: typeof fn, functionShape: typeof fn === 'function' ? { name: fn.name, length: fn.length, ownsPrototype: Object.hasOwn(fn, 'prototype'), functionText: Function.prototype.toString.call(fn) } : undefined, bodyBefore: before, bodyAfterCompile: globalThis.ownedCompilerBody, escapeAfterCompile: globalThis.ownedCompileEscape };
    if (invoke && typeof fn === 'function') {
      const mod = new Module(filename); mod.filename = filename;
      const actualRequire = Module.createRequire(filename);
      try { const value = fn.call(mod.exports, mod.exports, actualRequire, mod, filename, path.dirname(filename)); row.invoke = { status: 'returned', value: value === globalThis.ownedCompilerPromise ? { samePromise: true } : value, exports: mod.exports, bodyAfter: globalThis.ownedCompilerBody }; }
      catch (error) { row.invoke = { status: 'thrown', ...errorRecord(error), bodyAfter: globalThis.ownedCompilerBody }; }
    }
    rows.push(row);
  } catch (error) { rows.push({ id, status: 'thrown', ...errorRecord(error), bodyBefore: before, bodyAfterCompile: globalThis.ownedCompilerBody, escapeAfterCompile: globalThis.ownedCompileEscape }); }
  finally { if (throwWarning) process.removeListener('warning', warningListener); }
}
process.stdout.write(JSON.stringify({ authority: { nodeVersion: process.version, execPath: process.execPath, internalBinding: 'actual official contextify; expose-internals explicitly required' }, rows }) + '\n');

// Original official Node24 observer only; no candidate implementation imported.
// Root must admit --expose-internals and a fresh absolute owned fixture root.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import Module from 'node:module';
import { pathToFileURL } from 'node:url';
if (process.version !== 'v24.14.0') throw new Error('exact official Node24.14.0 required');
const require = Module.createRequire(import.meta.url);
const { internalBinding } = require('internal/test/binding');
const contextify = internalBinding('contextify');
const root = process.argv[2];
if (!root || !path.isAbsolute(root) || fs.existsSync(root)) throw new Error('fresh absolute owned fixture root required');
fs.mkdirSync(root, { recursive: false });
fs.mkdirSync(path.join(root, 'physical'));
fs.mkdirSync(path.join(root, 'logical'));
fs.writeFileSync(path.join(root, 'physical', 'dep.mjs'), 'export const marker=17;');
fs.writeFileSync(path.join(root, 'logical', 'dep.mjs'), 'export const marker=91;');
const saved = Object.getOwnPropertyDescriptor(Error, 'prepareStackTrace');
const rows = [];
const cases = [
  ['absent', 'return 1;'],
  ['both', 'return 1;\n//# sourceURL=logical.js\n//# sourceMappingURL=logical.map'],
  ['at-sign-and-tab', 'return 1;\n//@\tsourceURL=at.js\n//@\tsourceMappingURL=at.map'],
  ['no-mandatory-space', 'return 1;\n//#sourceURL=ignored.js'],
  ['two-spaces-before-name', 'return 1;\n//#  sourceURL=ignored.js'],
  ['space-before-equals-keeps-earlier', 'return 1;\n//# sourceURL=earlier.js\n//# sourceURL =ignored.js'],
  ['unknown-keeps-earlier', 'return 1;\n//# sourceURL=earlier.js\n//# unknown=later.js'],
  ['empty-clears-earlier', 'return 1;\n//# sourceURL=earlier.js\n//# sourceURL=\n//# sourceMappingURL=earlier.map\n//# sourceMappingURL='],
  ['junk-tail-clears-earlier', 'return 1;\n//# sourceURL=earlier.js\n//# sourceURL=later.js extra'],
  ['whitespace-tail-retained', 'return 1;\n//# sourceURL=later.js \t\u00a0'],
  ['unicode-white-and-value', 'return 1;\n//#\u00a0sourceURL=ümlaut🧪.js\u00a0'],
  ['quoted-values-raw', 'return 1;\n//# sourceURL="quoted.js"\n//# sourceMappingURL="quoted.map"'],
  ['nul-value-length', 'return 1;\n//# sourceURL=full\u0000logical.js'],
  ['line-separators', 'return 1;\u2028//# sourceURL=first.js\u2029//# sourceMappingURL=second.map'],
  ['only-actual-line-comment', 'void "//# sourceURL=string.js";void `\n//# sourceURL=template.js\n`;void /sourceURL=fake/;/* //# sourceURL=block.js */\n<!-- //# sourceURL=html.js\nreturn 1;'],
  ['comment-in-nested-body', 'return function nested(){\n//# sourceURL=nested-comment.js\nreturn 1};'],
];
function recordFrame(frame) {
  return { fileName: frame?.getFileName(), scriptNameOrSourceURL: frame?.getScriptNameOrSourceURL(), functionName: frame?.getFunctionName(), line: frame?.getLineNumber(), column: frame?.getColumnNumber() };
}
try {
  Error.prepareStackTrace = (error, frames) => frames;
  new vm.Script('globalThis.ownedMetaCapture=function ownedMetaCapture(){const target={};Error.captureStackTrace(target,ownedMetaCapture);return target.stack}', { filename: path.join(root, 'capture.js') }).runInThisContext();
  for (const [id, source] of cases) {
    const filename = path.join(root, 'physical', id + '.cjs');
    const result = contextify.compileFunctionForCJSLoader(source, filename, false, true);
    rows.push({ id, keys: Object.keys(result), sourceURL: result.sourceURL, sourceMapURL: result.sourceMapURL, cachedDataRejected: result.cachedDataRejected, canParseAsESM: result.canParseAsESM, functionType: typeof result.function });
  }
  const physical = path.join(root, 'physical', 'nested.cjs');
  const logical = pathToFileURL(path.join(root, 'logical', 'other.cjs')).href;
  const result = contextify.compileFunctionForCJSLoader('return function nested(){return {frames:ownedMetaCapture(),pending:import("./dep.mjs")}};\n//# sourceURL=' + logical, physical, false, true);
  const mod = new Module(physical); mod.filename = physical;
  const nested = result.function.call(mod.exports, mod.exports, Module.createRequire(physical), mod, physical, path.dirname(physical));
  const observed = nested();
  rows.push({ id: 'logical-frame-physical-import', sourceURL: result.sourceURL, frame: recordFrame(observed.frames[0]), importedMarker: (await observed.pending).marker });
  const script = new vm.Script('globalThis.ownedScriptBodyRuns=(globalThis.ownedScriptBodyRuns||0)+1;ownedMetaCapture();\n//# sourceURL=patched-script.js\n//# sourceMappingURL=patched.map', { filename: path.join(root, 'physical', 'patched.cjs') });
  const before = globalThis.ownedScriptBodyRuns;
  const frames = script.runInThisContext();
  rows.push({ id: 'patched-global-script', sourceMapURL: script.sourceMapURL, bodyBefore: before, bodyAfter: globalThis.ownedScriptBodyRuns, frame: recordFrame(frames[0]) });
  process.stdout.write(JSON.stringify({ authority: { node: process.version, execPath: process.execPath, commit: 'f657bb8ed86365ff3fdbe32e27563e778b41486a', capture: 'genuine contextify and vm.Script; no expected values or candidate imports' }, rows }) + '\n');
} finally {
  if (saved) Object.defineProperty(Error, 'prepareStackTrace', saved);
  else delete Error.prepareStackTrace;
}
